import SwiftUI
import AppKit

struct MainWindowView: View {
    @StateObject private var store = CompositionStore()
    @State private var dropHovering = false
    @State private var keyMonitor: Any? = nil

    var body: some View {
        ZStack {
            WindowBackdropView()
                .ignoresSafeArea()

            HStack(spacing: 12) {
                ImageListView(store: store)
                    .frame(width: 230)
                    .liquidGlassPanel(cornerRadius: 18)

                ZStack(alignment: .bottom) {
                    CanvasPreviewView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ExportBarView(store: store)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .liquidGlassPanel(cornerRadius: 22)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                InspectorView(store: store)
                    .frame(width: 272)
                    .liquidGlassPanel(cornerRadius: 18)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
        .frame(minWidth: 980, minHeight: 660)
        .onAppear {
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // 若焦点在文本输入框内，不拦截按键
                    if let responder = event.window?.firstResponder, responder is NSText {
                        return event
                    }
                    guard !store.composition.items.isEmpty else { return event }
                    let chars = event.charactersIgnoringModifiers ?? ""
                    if chars == "+" || chars == "=" {
                        store.stepCustomScale(increase: true)
                        return nil
                    } else if chars == "-" || chars == "_" {
                        store.stepCustomScale(increase: false)
                        return nil
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onDeleteCommand {
            store.removeSelected()
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.addImagesInBackground(from: urls)
            return true
        } isTargeted: { hovering in
            dropHovering = hovering
        }
        .overlay {
            if dropHovering {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if store.composition.items.isEmpty {
                EmptyDropHint {
                    store.openImagePicker()
                }
            }
        }
    }
}

private struct EmptyDropHint: View {
    let onPickImages: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("把图片从 Finder 拖到这里")
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
            Text("支持 PNG / JPEG / HEIC / WebP，可一次导入多张")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                onPickImages()
            } label: {
                Label("选择图片…", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 8)
            }
            .liquidGlassButtonStyle(prominent: true)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .liquidGlassPanel(cornerRadius: 24)
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }
}
