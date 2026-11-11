import SwiftUI
import AppKit

struct CanvasPreviewView: View {
    @ObservedObject var store: CompositionStore
    @State private var dragBase: (pairSum: Double, share: Double)? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = LayoutEngine.layout(store.composition)
            let scale = min(geo.size.width / layout.canvasSize.width,
                            geo.size.height / layout.canvasSize.height) * 0.94
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if !store.composition.items.isEmpty {
                    ScrollView([.vertical, .horizontal]) {
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color(cgColor: store.composition.backgroundColor))
                            ForEach(layout.placements, id: \.itemID) { p in
                                placementView(p, scale: scale)
                            }
                            boundaryHandles(layout: layout, scale: scale)
                        }
                        .frame(width: layout.canvasSize.width * scale,
                               height: layout.canvasSize.height * scale)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func placementView(_ p: SlicePlacement, scale: CGFloat) -> some View {
        let item = store.composition.items.first { $0.id == p.itemID }
        let selected = store.selectedID == p.itemID
        ZStack {
            if let item {
                let img = p.sourceRect.flatMap { item.thumbnail.cropping(to: $0) } ?? item.thumbnail
                Image(decorative: img, scale: 1)
                    .resizable()
                    .frame(width: p.fittedFrame.width * scale,
                           height: p.fittedFrame.height * scale)
                    .position(x: p.fittedFrame.midX * scale,
                              y: p.fittedFrame.midY * scale)
            }
        }
        .frame(width: p.destination.width * scale,
               height: p.destination.height * scale)
        .position(x: p.destination.midX * scale, y: p.destination.midY * scale)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = p.itemID }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
        )
    }

    @ViewBuilder
    private func boundaryHandles(layout: LayoutResult, scale: CGFloat) -> some View {
        let n = store.composition.items.count
        let vertical = store.composition.direction == .vertical
        ForEach(0..<max(0, n - 1), id: \.self) { i in
            let prev = layout.placements[i].destination
            let x = (vertical ? prev.midX : prev.maxX + CGFloat(store.composition.gap) / 2) * scale
            let y = (vertical ? prev.maxY + CGFloat(store.composition.gap) / 2 : prev.midY) * scale
            BoundaryHandle(vertical: vertical)
                .position(x: x, y: y)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            let w = store.composition.normalizedWeights
                            let S: Double
                            let baseShare: Double
                            if let d = dragBase {
                                (S, baseShare) = (d.pairSum, d.share)
                            } else {
                                S = w[i] + w[i + 1]
                                baseShare = S > 0 ? w[i] / S : 0.5
                                dragBase = (S, baseShare)
                            }
                            // 内容区归一化长度（同 LayoutEngine 口径）
                            let canvasLen = vertical ? Double(layout.canvasSize.height)
                                                     : Double(layout.canvasSize.width)
                            let stripTotal = canvasLen - 2 * store.composition.margin
                                - Double(n - 1) * store.composition.gap
                            guard stripTotal > 0, S > 0 else { return }
                            let delta = (vertical ? Double(g.translation.height)
                                                  : Double(g.translation.width))
                                / Double(scale) / stripTotal
                            store.setBoundary(i, share: baseShare + delta / S)
                        }
                        .onEnded { _ in dragBase = nil }
                )
        }
    }
}

private struct BoundaryHandle: View {
    let vertical: Bool
    var body: some View {
        ZStack {
            // 抓取区
            Rectangle().fill(.clear)
                .frame(width: vertical ? 60 : 22, height: vertical ? 22 : 60)
                .contentShape(Rectangle())
            // 视觉线
            Capsule()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: vertical ? 44 : 3, height: vertical ? 3 : 44)
        }
        .onHover { inside in
            if inside {
                (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
