import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportBarView: View {
    @ObservedObject var store: CompositionStore
    @State private var copied = false

    private var outputDimensionText: String {
        guard !store.composition.items.isEmpty else { return "" }
        let w = store.resolvedOutputWidth
        let h = Int((Double(w) / store.composition.aspectRatio.value).rounded())
        return "\(w) × \(h) px"
    }

    var body: some View {
        HStack(spacing: 14) {
            Picker("格式", selection: $store.exportFormat) {
                ForEach(ImageExporter.Format.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .labelsHidden()

            Picker("宽度", selection: $store.exportWidthOption) {
                Text(ExportWidthOption.original.label).tag(ExportWidthOption.original)
                Divider()
                ForEach(ExportWidthOption.fixedPresets, id: \.self) { w in
                    let opt = ExportWidthOption.fixed(w)
                    Text(opt.label).tag(opt)
                }
                Divider()
                ForEach(ExportWidthOption.percentPresets, id: \.self) { pct in
                    let opt = ExportWidthOption.percent(pct)
                    Text(opt.label).tag(opt)
                }
            }
            .frame(width: 90)
            .labelsHidden()
            .help("选择导出宽度或按原图百分比缩放")

            if !outputDimensionText.isEmpty {
                Text(outputDimensionText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 12)

            Button {
                copyToClipboard()
            } label: {
                Label(copied ? "已复制" : "复制",
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .liquidGlassButtonStyle()
            .fixedSize()
            .keyboardShortcut("c", modifiers: .command)
            .disabled(store.composition.items.isEmpty)

            Button {
                exportToFile()
            } label: {
                Label("导出…", systemImage: "square.and.arrow.down")
            }
            .liquidGlassButtonStyle(prominent: true)
            .fixedSize()
            .keyboardShortcut("s", modifiers: .command)
            .disabled(store.composition.items.isEmpty)
        }
        .controlSize(.regular)
    }

    private func copyToClipboard() {
        let composition = store.composition
        let width = store.resolvedOutputWidth
        Task.detached(priority: .userInitiated) {
            guard let img = CompositionRenderer.render(composition, outputWidth: width) else { return }
            await MainActor.run {
                ImageExporter.copyToClipboard(img)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
        }
    }

    private func exportToFile() {
        // 先让用户确认保存位置，取消时不做渲染/编码（终审 Important 3）
        let panel = NSSavePanel()
        let format = store.exportFormat
        panel.allowedContentTypes = [format.utType]
        let ext = format.fileExtension
        panel.nameFieldStringValue = "PicPin-\(Int(Date().timeIntervalSince1970)).\(ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let composition = store.composition
        let width = store.resolvedOutputWidth
        Task.detached(priority: .userInitiated) {
            guard let img = CompositionRenderer.render(composition, outputWidth: width),
                  let data = ImageExporter.encode(img, format: format) else {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "导出失败"
                    alert.informativeText = "图片渲染或编码失败，请检查目标比例是否过于极端。"
                    _ = alert.runModal()
                }
                return
            }
            do {
                try data.write(to: url)
            } catch {
                await MainActor.run {
                    _ = NSAlert(error: error).runModal()
                }
            }
        }
    }
}
