import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ExportWidthOption: Hashable, Identifiable {
    case original
    case fixed(Int)      // 1080, 1440, 2048
    case percent(Int)    // 25, 50, 75, 100

    var id: String { label }

    var label: String {
        switch self {
        case .original: return "原始"
        case .fixed(let w): return "\(w)"
        case .percent(let pct): return "\(pct)%"
        }
    }

    static let fixedPresets: [Int] = [1080, 1440, 2048]
    static let percentPresets: [Int] = [25, 50, 75, 100]

    static let allOptions: [ExportWidthOption] =
        [.original]
        + fixedPresets.map { .fixed($0) }
        + percentPresets.map { .percent($0) }
}

@MainActor
final class CompositionStore: ObservableObject {
    @Published var composition = Composition()
    @Published var selectedID: UUID?
    @Published var exportWidthOption: ExportWidthOption = .original
    @Published var exportFormat: ImageExporter.Format = .png
    @Published var lastIgnoredCount = 0
    /// 默认勾选：修改策略时同步应用到全部图片；取消勾选时仅作用于当前选中图片
    @Published var syncPolicyToAll: Bool = true {
        didSet {
            if syncPolicyToAll, let sel = selectedID ?? composition.items.first?.id {
                applyPolicyToAll(from: sel)
            }
        }
    }

    /// 追加图片：保留旧条相对比例，新条各占 1/(n+k)；非图片计数到 lastIgnoredCount。
    /// 同步解码版（测试/小批量用）；UI 拖放入口请用 addImagesInBackground。
    func addImages(from urls: [URL]) {
        var loaded: [ImageItem] = []
        var ignored = 0
        for url in urls {
            if Self.isImageURL(url), let item = ImageLoader.loadItem(from: url) {
                loaded.append(item)
            } else {
                ignored += 1
            }
        }
        apply(loaded: loaded, ignored: ignored)
    }

    /// UI 拖放入口：后台解码（原图 + EXIF 重栅格化是大开销），主线程回写状态
    func addImagesInBackground(from urls: [URL]) {
        Task.detached(priority: .userInitiated) {
            let result = CompositionStore.loadImages(from: urls)
            let loaded = result.loaded, ignored = result.ignored
            await MainActor.run { [weak self] in
                self?.apply(loaded: loaded, ignored: ignored)
            }
        }
    }

    private nonisolated static func loadImages(from urls: [URL]) -> (loaded: [ImageItem], ignored: Int) {
        var loaded: [ImageItem] = []
        var ignored = 0
        for url in urls {
            if CompositionStore.isImageURL(url), let item = ImageLoader.loadItem(from: url) {
                loaded.append(item)
            } else {
                ignored += 1
            }
        }
        return (loaded, ignored)
    }

    private func apply(loaded: [ImageItem], ignored: Int) {
        lastIgnoredCount = ignored
        guard !loaded.isEmpty else { return }
        var c = composition
        let templatePolicy: SlicePolicy? = {
            guard syncPolicyToAll, let refID = selectedID ?? c.items.first?.id else { return nil }
            var p = c.policy(for: refID)
            let v = p.alignment.defaultOffset
            p.customOffsetX = v
            p.customOffsetY = v
            return p
        }()
        let n = c.items.count, k = loaded.count, total = n + k
        var w = c.normalizedWeights.map { $0 * Double(n) / Double(total) }
        w += Array(repeating: 1.0 / Double(total), count: k)
        c.items += loaded
        c.weights = w
        if let templatePolicy {
            for item in loaded {
                c.policies[item.id] = templatePolicy
            }
        }
        composition = c
        if selectedID == nil {
            selectedID = c.items.first?.id
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        var items = composition.items
        var weights = composition.normalizedWeights
        items.move(fromOffsets: source, toOffset: destination)
        weights.move(fromOffsets: source, toOffset: destination)
        composition.items = items
        composition.weights = weights
    }

    func remove(at offsets: IndexSet) {
        var items = composition.items
        var weights = composition.normalizedWeights
        items.remove(atOffsets: offsets)
        weights.remove(atOffsets: offsets)
        composition.items = items
        composition.weights = weights
        let ids = Set(items.map(\.id))
        composition.policies = composition.policies.filter { ids.contains($0.key) }
        if let sel = selectedID, !ids.contains(sel) { selectedID = nil }
    }

    func resetToEven() {
        composition.weights = []                              // 均分兜底
    }

    func clearAll() {
        composition.items = []
        composition.weights = []
        composition.policies = [:]
        selectedID = nil
        lastIgnoredCount = 0
    }

    func removeSelected() {
        guard let sel = selectedID,
              let idx = composition.items.firstIndex(where: { $0.id == sel }) else { return }
        remove(at: IndexSet(integer: idx))
    }

    func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "导入"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        addImagesInBackground(from: panel.urls)
    }

    func setBoundary(_ index: Int, share: Double) {
        composition.setBoundary(index, share: share)
    }

    func setMode(_ mode: FitMode, for id: UUID) {
        if syncPolicyToAll {
            var policies = composition.policies
            for item in composition.items {
                var p = composition.policy(for: item.id)
                p.mode = mode
                policies[item.id] = p
            }
            composition.policies = policies
        } else {
            var p = composition.policy(for: id)
            p.mode = mode
            composition.policies[id] = p
        }
    }

    func setAlignment(_ alignment: CropAlignment, for id: UUID) {
        let v = alignment.defaultOffset
        if syncPolicyToAll {
            var policies = composition.policies
            for item in composition.items {
                var p = composition.policy(for: item.id)
                p.alignment = alignment
                p.customOffsetX = v
                p.customOffsetY = v
                policies[item.id] = p
            }
            composition.policies = policies
        } else {
            var p = composition.policy(for: id)
            p.alignment = alignment
            p.customOffsetX = v
            p.customOffsetY = v
            composition.policies[id] = p
        }
    }

    func resetOffset(for id: UUID) {
        var p = composition.policy(for: id)
        let v = p.alignment.defaultOffset
        p.customOffsetX = v
        p.customOffsetY = v
        composition.policies[id] = p
    }

    /// 获取某张图片当前的等效自定义缩放倍率（1.0 = 100%）
    func currentEffectiveScale(for id: UUID) -> Double {
        let p = composition.policy(for: id)
        if p.mode == .custom {
            return p.customScale
        }
        let layout = LayoutEngine.layout(composition)
        if let placement = layout.placements.first(where: { $0.itemID == id }) {
            return placement.effectiveRelativeScale
        }
        return 1.0
    }

    /// 设置自定义缩放倍率（自动切换为 .custom 模式；遵循 syncPolicyToAll）
    func setCustomScale(_ scale: Double, for id: UUID) {
        let clamped = max(0.01, scale)
        if syncPolicyToAll {
            var policies = composition.policies
            for item in composition.items {
                var p = composition.policy(for: item.id)
                p.mode = .custom
                p.customScale = clamped
                policies[item.id] = p
            }
            composition.policies = policies
        } else {
            var p = composition.policy(for: id)
            p.mode = .custom
            p.customScale = clamped
            composition.policies[id] = p
        }
    }

    /// 键盘快捷键 + / - 步进调整图片大小（不受 10%~400% 限制）
    func stepCustomScale(increase: Bool) {
        guard let targetID = selectedID ?? composition.items.first?.id else { return }
        let current = currentEffectiveScale(for: targetID)
        let next: Double
        if increase {
            next = current < 0.2 ? current * 1.2 : current + 0.1
        } else {
            next = current <= 0.2 ? max(0.01, current / 1.2) : max(0.01, current - 0.1)
        }
        setCustomScale(next, for: targetID)
    }

    func applyPolicyToAll(from sourceID: UUID) {
        var basePolicy = composition.policy(for: sourceID)
        let v = basePolicy.alignment.defaultOffset
        basePolicy.customOffsetX = v
        basePolicy.customOffsetY = v
        var policies = composition.policies
        for item in composition.items {
            policies[item.id] = basePolicy
        }
        composition.policies = policies
    }

    /// 在画布中拖动单张小图调整位置（1:1 跟手平移，支持 fill / fit / custom 任意缩放状态）
    func panImage(_ id: UUID,
                  baseOffsets: (x: Double, y: Double),
                  deltaCanvas: CGSize,
                  placement: SlicePlacement) {
        var p = composition.policy(for: id)
        var newX = baseOffsets.x
        var newY = baseOffsets.y
        let eps = 0.5
        let diffX = Double(placement.imageFrame.width - placement.destination.width)
        if diffX > eps {
            newX = min(max(baseOffsets.x - Double(deltaCanvas.width) / diffX, 0), 1)
        } else if -diffX > eps {
            newX = min(max(baseOffsets.x + Double(deltaCanvas.width) / (-diffX), 0), 1)
        }

        let diffY = Double(placement.imageFrame.height - placement.destination.height)
        if diffY > eps {
            newY = min(max(baseOffsets.y - Double(deltaCanvas.height) / diffY, 0), 1)
        } else if -diffY > eps {
            newY = min(max(baseOffsets.y + Double(deltaCanvas.height) / (-diffY), 0), 1)
        }
        p.customOffsetX = newX
        p.customOffsetY = newY
        composition.policies[id] = p
    }

    var exportWidth: Int {
        get {
            switch exportWidthOption {
            case .fixed(let w): return w
            case .original, .percent: return 0
            }
        }
        set {
            exportWidthOption = newValue > 0 ? .fixed(newValue) : .original
        }
    }

    var baseOriginalWidth: Int {
        composition.items.map { Int($0.pixelSize.width) }.max() ?? 1000
    }

    var resolvedOutputWidth: Int {
        switch exportWidthOption {
        case .original:
            return max(1, baseOriginalWidth)
        case .fixed(let w):
            return max(1, w)
        case .percent(let pct):
            let scale = Double(max(1, pct)) / 100.0
            return max(1, Int((Double(baseOriginalWidth) * scale).rounded()))
        }
    }

    private nonisolated static func isImageURL(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .image)
    }
}
