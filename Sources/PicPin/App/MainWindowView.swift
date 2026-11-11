import SwiftUI

struct MainWindowView: View {
    @StateObject private var store = CompositionStore()
    @State private var dropHovering = false

    var body: some View {
        HStack(spacing: 0) {
            ImageListView(store: store)
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                CanvasPreviewView(store: store)   // Task 9 实现
                Divider()
                ExportBarView(store: store)       // Task 11 实现
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            InspectorView(store: store)           // Task 10 实现
                .frame(width: 260)
        }
        .frame(minWidth: 960, minHeight: 640)
        .dropDestination(for: URL.self) { urls, _ in
            store.addImagesInBackground(from: urls)
            return true
        } isTargeted: { hovering in
            dropHovering = hovering
        }
        .overlay {
            if dropHovering {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if store.composition.items.isEmpty {
                EmptyDropHint()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct EmptyDropHint: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("把图片从 Finder 拖到这里")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("支持 PNG / JPEG / HEIC / WebP，可一次拖入多张")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
