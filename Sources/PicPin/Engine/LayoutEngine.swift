import CoreGraphics
import Foundation

struct SlicePlacement: Equatable {
    let itemID: UUID
    let destination: CGRect   // 左上原点，归一化画布坐标（宽 = LayoutEngine.base）
    let sourceRect: CGRect?   // CGImage 像素坐标（左上原点）；nil = 整图无裁剪
    let fittedFrame: CGRect   // fill == destination；fit 为条带内实际图像 frame（四周留白）
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
    /// fill：scale = max(...)，比值大的轴恰好贴合、另一轴溢出：
    ///   - 主轴（对齐生效轴：垂直→y，水平→x）溢出 → 按 policy.alignment 裁剪（本任务实现）
    ///   - 副轴溢出 → 居中裁剪（Task 4 测试驱动补上）
    private static func placement(item: ImageItem, policy: SlicePolicy,
                                  strip: CGRect, direction: StitchDirection) -> SlicePlacement {
        let imgW = CGFloat(item.cgImage.width)
        let imgH = CGFloat(item.cgImage.height)
        guard imgW > 0, imgH > 0, strip.width > 0, strip.height > 0 else {
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: nil, fittedFrame: strip)
        }
        switch policy.mode {
        case .fill:
            let scale = max(strip.width / imgW, strip.height / imgH)
            let eps: CGFloat = 0.5                          // 归一化单位下的显示容差
            var srcX: CGFloat = 0, srcY: CGFloat = 0
            var srcW = imgW, srcH = imgH
            var cropped = false
            // 主轴：垂直→y（对齐策略），水平→x
            if direction == .vertical, imgH * scale > strip.height + eps {
                srcH = strip.height / scale
                srcY = axisOrigin(alignment: policy.alignment, imageLen: imgH, keepLen: srcH)
                cropped = true
            }
            if direction == .horizontal, imgW * scale > strip.width + eps {
                srcW = strip.width / scale
                srcX = axisOrigin(alignment: policy.alignment, imageLen: imgW, keepLen: srcW)
                cropped = true
            }
            let src = cropped ? CGRect(x: srcX, y: srcY, width: srcW, height: srcH) : nil
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: src, fittedFrame: strip)
        case .fit:
            let scale = min(strip.width / imgW, strip.height / imgH)
            let w = imgW * scale, h = imgH * scale
            let frame = CGRect(x: strip.midX - w / 2, y: strip.midY - h / 2, width: w, height: h)
            return SlicePlacement(itemID: item.id, destination: strip, sourceRect: nil, fittedFrame: frame)
        }
    }

    private static func axisOrigin(alignment: CropAlignment, imageLen: CGFloat, keepLen: CGFloat) -> CGFloat {
        switch alignment {
        case .start: return 0
        case .center: return (imageLen - keepLen) / 2
        case .end: return imageLen - keepLen
        }
    }
}
