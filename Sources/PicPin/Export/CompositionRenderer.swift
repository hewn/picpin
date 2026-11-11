import CoreGraphics
import Foundation

enum CompositionRenderer {
    /// 按输出像素宽度渲染（高度 = 宽度 / 比例）。使用原始 CGImage，保证导出保真。
    static func render(_ c: Composition, outputWidth: Int) -> CGImage? {
        let layout = LayoutEngine.layout(c)
        let scale = CGFloat(outputWidth) / LayoutEngine.base
        let W = Int((layout.canvasSize.width * scale).rounded())
        let H = Int((layout.canvasSize.height * scale).rounded())
        guard W > 0, H > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(c.backgroundColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .high
        for p in layout.placements {
            guard let item = c.items.first(where: { $0.id == p.itemID }) else { continue }
            // 布局左上原点 → CG 左下原点；通过条带 clip + 完整等比 imageFrame 绘制，消除像素取整拉伸误差
            let destRect = CGRect(x: p.destination.minX * scale,
                                  y: CGFloat(H) - (p.destination.minY + p.destination.height) * scale,
                                  width: p.destination.width * scale,
                                  height: p.destination.height * scale)
            let imgRect = CGRect(x: p.imageFrame.minX * scale,
                                 y: CGFloat(H) - (p.imageFrame.minY + p.imageFrame.height) * scale,
                                 width: p.imageFrame.width * scale,
                                 height: p.imageFrame.height * scale)
            ctx.saveGState()
            ctx.clip(to: destRect)
            ctx.draw(item.cgImage, in: imgRect)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
