import CoreGraphics
import Foundation

struct SlicePlacement: Equatable {
    let itemID: UUID
    let destination: CGRect   // 左上原点，归一化画布坐标（宽 = LayoutEngine.base）
    let sourceRect: CGRect?   // CGImage 像素坐标（左上原点）；nil = 整图无裁剪
    let fittedFrame: CGRect   // fill == destination；fit 为条带内实际图像 frame（四周留白）
    let imageFrame: CGRect    // 图像按原图宽高比等比缩放后的完整画布坐标 frame（由 destination 裁剪）
    let offsetX: Double       // 当前生效的水平归一化偏移 [0, 1]
    let offsetY: Double       // 当前生效的垂直归一化偏移 [0, 1]

    init(itemID: UUID,
         destination: CGRect,
         sourceRect: CGRect?,
         fittedFrame: CGRect,
         imageFrame: CGRect? = nil,
         offsetX: Double = 0.5,
         offsetY: Double = 0.5) {
        self.itemID = itemID
        self.destination = destination
        self.sourceRect = sourceRect
        self.fittedFrame = fittedFrame
        self.imageFrame = imageFrame ?? fittedFrame
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// 图像在条带（destination）局部坐标系中的 frame——供条带局部渲染的视图使用
    ///（终审 Critical 1：嵌套 .position 必须用条带内相对坐标，而非画布绝对坐标）
    var localFittedFrame: CGRect {
        CGRect(x: fittedFrame.minX - destination.minX,
               y: fittedFrame.minY - destination.minY,
               width: fittedFrame.width,
               height: fittedFrame.height)
    }

    /// 完整等比图像在条带（destination）局部坐标系中的 frame（配合条带 .clipped() 彻底避免裁剪取整导致的拉伸）
    var localImageFrame: CGRect {
        CGRect(x: imageFrame.minX - destination.minX,
               y: imageFrame.minY - destination.minY,
               width: imageFrame.width,
               height: imageFrame.height)
    }

    /// 当前条带内图像主要可移动的轴（用于 UI 展示对齐方向与拖动提示）
    func activeAxis(fallback: StitchDirection) -> StitchDirection {
        let dx = abs(imageFrame.width - destination.width)
        let dy = abs(imageFrame.height - destination.height)
        if dx > 0.5 && dy <= 0.5 { return .horizontal }
        if dy > 0.5 && dx <= 0.5 { return .vertical }
        return fallback
    }

    /// 当前图像相对于条带完整显示（fit 100%）的等效缩放倍率
    var effectiveRelativeScale: Double {
        guard destination.width > 0, destination.height > 0,
              imageFrame.width > 0, imageFrame.height > 0 else { return 1.0 }
        let fitScale = min(destination.width / imageFrame.width, destination.height / imageFrame.height)
        guard fitScale > 0 else { return 1.0 }
        return Double(1.0 / fitScale)
    }
}

struct LayoutResult: Equatable {
    let canvasSize: CGSize
    let placements: [SlicePlacement]
}

enum LayoutEngine {
    static let base: CGFloat = 1000

    static func layout(_ c: Composition) -> LayoutResult {
        let W = base
        let H = base / CGFloat(c.aspectRatio.value)
        let canvas = CGSize(width: W, height: H)
        let n = c.items.count
        guard n > 0 else { return LayoutResult(canvasSize: canvas, placements: []) }

        let m = CGFloat(c.margin)
        let gap = CGFloat(c.gap)
        let weights = c.normalizedWeights
        let contentOrigin = CGPoint(x: m, y: m)
        let contentW = max(0, W - 2 * m)
        let contentH = max(0, H - 2 * m)

        var placements: [SlicePlacement] = []
        if c.direction == .vertical {
            let stripTotal = max(0, contentH - CGFloat(n - 1) * gap)
            var y = contentOrigin.y
            for (i, item) in c.items.enumerated() {
                let strip = CGRect(x: contentOrigin.x, y: y, width: contentW,
                                   height: stripTotal * CGFloat(weights[i]))
                placements.append(placement(item: item, policy: c.policy(for: item.id),
                                            strip: strip, direction: .vertical))
                y += strip.height + gap
            }
        } else {
            let stripTotal = max(0, contentW - CGFloat(n - 1) * gap)
            var x = contentOrigin.x
            for (i, item) in c.items.enumerated() {
                let strip = CGRect(x: x, y: contentOrigin.y,
                                   width: stripTotal * CGFloat(weights[i]), height: contentH)
                placements.append(placement(item: item, policy: c.policy(for: item.id),
                                            strip: strip, direction: .horizontal))
                x += strip.width + gap
            }
        }
        return LayoutResult(canvasSize: canvas, placements: placements)
    }

    /// 单条带内几何。坐标系：左上原点。
    private static func placement(item: ImageItem, policy: SlicePolicy,
                                  strip: CGRect, direction: StitchDirection) -> SlicePlacement {
        let imgW = CGFloat(item.cgImage.width)
        let imgH = CGFloat(item.cgImage.height)
        guard imgW > 0, imgH > 0, strip.width > 0, strip.height > 0 else {
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: nil, fittedFrame: strip)
        }
        let ox = min(max(policy.customOffsetX ?? (direction == .horizontal ? policy.alignment.defaultOffset : 0.5), 0), 1)
        let oy = min(max(policy.customOffsetY ?? (direction == .vertical ? policy.alignment.defaultOffset : 0.5), 0), 1)

        switch policy.mode {
        case .fill:
            let scale = max(strip.width / imgW, strip.height / imgH)
            let drawW = imgW * scale
            let drawH = imgH * scale
            let overflowX = max(0, drawW - strip.width)
            let overflowY = max(0, drawH - strip.height)
            let imgFrame = CGRect(
                x: strip.minX - CGFloat(ox) * overflowX,
                y: strip.minY - CGFloat(oy) * overflowY,
                width: drawW,
                height: drawH
            )
            let eps: CGFloat = 0.5                          // 归一化单位下的显示容差
            var srcX: CGFloat = 0, srcY: CGFloat = 0
            var srcW = imgW, srcH = imgH
            var cropped = false
            if overflowY > eps {
                srcH = strip.height / scale
                srcY = CGFloat(oy) * (imgH - srcH)
                cropped = true
            }
            if overflowX > eps {
                srcW = strip.width / scale
                srcX = CGFloat(ox) * (imgW - srcW)
                cropped = true
            }
            let src = cropped ? CGRect(x: srcX, y: srcY, width: srcW, height: srcH) : nil
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: src,
                                  fittedFrame: strip, imageFrame: imgFrame,
                                  offsetX: ox, offsetY: oy)
        case .fit:
            let scale = min(strip.width / imgW, strip.height / imgH)
            let w = imgW * scale, h = imgH * scale
            let slackX = max(0, strip.width - w)
            let slackY = max(0, strip.height - h)
            let frame = CGRect(
                x: strip.minX + CGFloat(ox) * slackX,
                y: strip.minY + CGFloat(oy) * slackY,
                width: w,
                height: h
            )
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: nil,
                                  fittedFrame: frame, imageFrame: frame,
                                  offsetX: ox, offsetY: oy)
        case .custom:
            let baseScale = min(strip.width / imgW, strip.height / imgH)
            let userScale = max(0.01, CGFloat(policy.customScale))
            let scale = baseScale * userScale
            let drawW = imgW * scale
            let drawH = imgH * scale

            let imgX: CGFloat
            if drawW <= strip.width {
                imgX = strip.minX + CGFloat(ox) * (strip.width - drawW)
            } else {
                imgX = strip.minX - CGFloat(ox) * (drawW - strip.width)
            }

            let imgY: CGFloat
            if drawH <= strip.height {
                imgY = strip.minY + CGFloat(oy) * (strip.height - drawH)
            } else {
                imgY = strip.minY - CGFloat(oy) * (drawH - strip.height)
            }

            let imgFrame = CGRect(x: imgX, y: imgY, width: drawW, height: drawH)
            let visible = imgFrame.intersection(strip)
            let fitted = visible.isNull ? CGRect(x: strip.midX, y: strip.midY, width: 0, height: 0) : visible

            let eps: CGFloat = 0.5
            let overflowX = max(0, drawW - strip.width)
            let overflowY = max(0, drawH - strip.height)
            var srcX: CGFloat = 0, srcY: CGFloat = 0
            var srcW = imgW, srcH = imgH
            var cropped = false
            if overflowY > eps {
                srcH = strip.height / scale
                srcY = CGFloat(oy) * (imgH - srcH)
                cropped = true
            }
            if overflowX > eps {
                srcW = strip.width / scale
                srcX = CGFloat(ox) * (imgW - srcW)
                cropped = true
            }
            let src = cropped ? CGRect(x: srcX, y: srcY, width: srcW, height: srcH) : nil
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: src,
                                  fittedFrame: fitted, imageFrame: imgFrame,
                                  offsetX: ox, offsetY: oy)
        }
    }
}
