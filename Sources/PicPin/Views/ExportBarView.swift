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

    private func renderedImage() -> CGImage? {
        CompositionRenderer.render(store.composition, outputWidth: store.resolvedOutputWidth)
    }

    private func copyToClipboard() {
        guard let img = renderedImage() else { return }
        ImageExporter.copyToClipboard(img)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func exportToFile() {
        guard let img = renderedImage(),
              let data = ImageExporter.encode(img, format: store.exportFormat) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [store.exportFormat == .png ? .png : .jpeg]
        let ext = store.exportFormat == .png ? "png" : "jpg"
        panel.nameFieldStringValue = "PicPin-\(Int(Date().timeIntervalSince1970)).\(ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
