import SwiftUI
import AppKit

struct CanvasPreviewView: View {
    @ObservedObject var store: CompositionStore
    @State private var dragBase: (pairSum: Double, share: Double)? = nil
    @State private var pinchBaseScale: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = LayoutEngine.layout(store.composition)
            let availW = max(100, geo.size.width)
            let availH = max(100, geo.size.height - 124)
            let rawScale = min(availW / layout.canvasSize.width,
                               availH / layout.canvasSize.height) * 0.92
            let scale = max(0.01, rawScale.isFinite ? rawScale : 0.1)
            ZStack {
                Color.clear
                if !store.composition.items.isEmpty {
                    CanvasContentView(store: store, layout: layout, scale: scale,
                                      dragBase: $dragBase)
                        .frame(width: layout.canvasSize.width * scale,
                               height: layout.canvasSize.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(cgColor: store.composition.backgroundColor))
                                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                        )
                        .padding(.top, 52)
                        .padding(.bottom, 64)

                    VStack {
                        CanvasScaleBarView(store: store, layout: layout)
                            .padding(.top, 6)
                        Spacer()
                    }
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { mag in
                        guard let targetID = store.selectedID ?? store.composition.items.first?.id else { return }
                        let base: Double
                        if let b = pinchBaseScale {
                            base = b
                        } else {
                            base = store.currentEffectiveScale(for: targetID)
                            pinchBaseScale = base
                        }
                        store.setCustomScale(base * Double(mag), for: targetID)
                    }
                    .onEnded { _ in
                        pinchBaseScale = nil
                    }
            )
        }
    }
}

/// 画布拼接区顶部的液态玻璃缩放控制条（10%~400% 滑动条 + 25%/50%/75%/100%/150%/200% 快捷选项）
private struct CanvasScaleBarView: View {
    @ObservedObject var store: CompositionStore
    let layout: LayoutResult

    private static let presets: [(label: String, value: Double)] = [
        ("25%", 0.25),
        ("50%", 0.50),
        ("75%", 0.75),
        ("100%", 1.00),
        ("150%", 1.50),
        ("200%", 2.00),
    ]

    private var activeID: UUID? {
        store.selectedID ?? store.composition.items.first?.id
    }

    private var currentScale: Double {
        guard let id = activeID else { return 1.0 }
        let p = store.composition.policy(for: id)
        if p.mode == .custom {
            return p.customScale
        }
        return layout.placements.first(where: { $0.itemID == id })?.effectiveRelativeScale ?? 1.0
    }

    var body: some View {
        if let id = activeID {
            let scaleVal = currentScale
            let pct = Int((scaleVal * 100).rounded())
            HStack(spacing: 8) {
                Button {
                    store.stepCustomScale(increase: false)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .liquidGlassButtonStyle()
                .controlSize(.small)
                .help("缩小 (-)")

                Slider(
                    value: Binding(
                        get: { min(max(scaleVal, 0.10), 4.00) },
                        set: { store.setCustomScale($0, for: id) }
                    ),
                    in: 0.10...4.00
                )
                .frame(width: 130)

                Button {
                    store.stepCustomScale(increase: true)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .liquidGlassButtonStyle()
                .controlSize(.small)
                .help("放大 (+)")

                Text("\(pct)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 44, alignment: .trailing)

                Divider()
                    .frame(height: 14)
                    .opacity(0.35)

                HStack(spacing: 4) {
                    ForEach(Self.presets, id: \.value) { preset in
                        let isSelected = store.composition.policy(for: id).mode == .custom
                            && abs(scaleVal - preset.value) < 0.005
                        Button {
                            store.setCustomScale(preset.value, for: id)
                        } label: {
                            Text(preset.label)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(LiquidGlassChipButtonStyle(isSelected: isSelected))
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlassPanel(cornerRadius: 18)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .fixedSize()
        }
    }
}

/// 画布本体（ScrollView 内容）：条带渲染 + 边界手柄。
/// 独立成视图以便 ImageRenderer 直接渲染做回归测试（ScrollView 离屏不渲染）。
struct CanvasContentView: View {
    @ObservedObject var store: CompositionStore
    let layout: LayoutResult
    let scale: CGFloat
    @Binding var dragBase: (pairSum: Double, share: Double)?
    @State private var panBases: [UUID: (x: Double, y: Double)] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(cgColor: store.composition.backgroundColor))
            ForEach(layout.placements, id: \.itemID) { p in
                placementView(p)
            }
            boundaryHandles
        }
        .coordinateSpace(name: "canvas")
    }

    @ViewBuilder
    private func placementView(_ p: SlicePlacement) -> some View {
        let item = store.composition.items.first { $0.id == p.itemID }
        let selected = store.selectedID == p.itemID
        let localImg = p.localImageFrame
        ZStack {
            if let item {
                // 直接以完整等比 imageFrame 绘制原缩略图，由外层条带 frame + .clipped() 裁剪，彻底避免拉伸变形
                Image(decorative: item.thumbnail, scale: 1)
                    .resizable()
                    .frame(width: localImg.width * scale,
                           height: localImg.height * scale)
                    .position(x: localImg.midX * scale, y: localImg.midY * scale)
            }
        }
        .frame(width: p.destination.width * scale,
               height: p.destination.height * scale)
        .clipped()
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .onTapGesture {
            store.selectedID = p.itemID
        }
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                .onChanged { g in
                    guard scale > 0 else { return }
                    if store.selectedID != p.itemID {
                        store.selectedID = p.itemID
                    }
                    let base: (x: Double, y: Double)
                    if let b = panBases[p.itemID] {
                        base = b
                    } else {
                        base = (p.offsetX, p.offsetY)
                        panBases[p.itemID] = base
                    }
                    let deltaCanvas = CGSize(
                        width: g.translation.width / scale,
                        height: g.translation.height / scale
                    )
                    store.panImage(p.itemID, baseOffsets: base, deltaCanvas: deltaCanvas, placement: p)
                }
                .onEnded { _ in
                    panBases[p.itemID] = nil
                }
        )
        .position(x: p.destination.midX * scale, y: p.destination.midY * scale)
    }

    @ViewBuilder
    private var boundaryHandles: some View {
        let n = store.composition.items.count
        let vertical = store.composition.direction == .vertical
        ForEach(0..<max(0, n - 1), id: \.self) { i in
            let prev = layout.placements[i].destination
            let x = (vertical ? prev.midX : prev.maxX + CGFloat(store.composition.gap) / 2) * scale
            let y = (vertical ? prev.maxY + CGFloat(store.composition.gap) / 2 : prev.midY) * scale
            BoundaryHandle(vertical: vertical)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
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
                            guard stripTotal > 0, S > 0, scale > 0 else { return }
                            let delta = (vertical ? Double(g.translation.height)
                                                  : Double(g.translation.width))
                                / Double(scale) / stripTotal
                            store.setBoundary(i, share: baseShare + delta / S)
                        }
                        .onEnded { _ in dragBase = nil }
                )
                .onTapGesture(count: 2) {
                    store.resetToEven()
                }
                .help("拖拽微调占比，双击恢复均分")
                .position(x: x, y: y)
        }
    }
}

private struct BoundaryHandle: View {
    let vertical: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            // 抓取区
            Rectangle().fill(.clear)
                .frame(width: vertical ? 64 : 24, height: vertical ? 24 : 64)
                .contentShape(Rectangle())
            // 液态玻璃胶囊手柄
            Capsule()
                .fill(hovering ? Color.accentColor : Color.accentColor.opacity(0.85))
                .frame(width: vertical ? (hovering ? 52 : 44) : (hovering ? 5 : 4),
                       height: vertical ? (hovering ? 5 : 4) : (hovering ? 52 : 44))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .onHover { inside in
            hovering = inside
            if inside {
                (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }
}
