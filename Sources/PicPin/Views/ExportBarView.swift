import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportBarView: View {
    @ObservedObject var store: CompositionStore
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Picker("格式", selection: $store.exportFormat) {
                ForEach(ImageExporter.Format.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .labelsHidden()

            Picker("宽度", selection: $store.exportWidth) {
                Text("1080").tag(1080)
                Text("1242").tag(1242)
                Text("1440").tag(1440)
                Text("2048").tag(2048)
                Text("原始").tag(0)
            }
            .frame(width: 110)
            .labelsHidden()

            Spacer()

            Button {
                copyToClipboard()
            } label: {
                Label(copied ? "已复制" : "复制到剪贴板",
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .disabled(store.composition.items.isEmpty)

            Button {
                exportToFile()
            } label: {
                Label("导出…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
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
        panel.allowedContentTypes = [format == .png ? .png : .jpeg]
        let ext = format == .png ? "png" : "jpg"
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
