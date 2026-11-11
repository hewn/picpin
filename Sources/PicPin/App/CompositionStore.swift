import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class CompositionStore: ObservableObject {
    @Published var composition = Composition()
    @Published var selectedID: UUID?
    @Published var exportWidth: Int = 1242                   // 0 = 原始最大宽度
    @Published var exportFormat: ImageExporter.Format = .png
    @Published var lastIgnoredCount = 0

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
        let n = c.items.count, k = loaded.count, total = n + k
        var w = c.normalizedWeights.map { $0 * Double(n) / Double(total) }
        w += Array(repeating: 1.0 / Double(total), count: k)
        c.items += loaded
        c.weights = w
        composition = c
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

    func setBoundary(_ index: Int, share: Double) {
        composition.setBoundary(index, share: share)
    }

    var resolvedOutputWidth: Int {
        if exportWidth > 0 { return exportWidth }
        return composition.items.map { Int($0.pixelSize.width) }.max() ?? 1000
    }

    private nonisolated static func isImageURL(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .image)
    }
}
