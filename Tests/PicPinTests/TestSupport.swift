import CoreGraphics

enum TestSupport {
    /// 生成指定尺寸的纯色 CGImage（sRGB, 8bit）
    static func makeImage(width: Int, height: Int, color: (CGFloat, CGFloat, CGFloat)) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// 生成 32x32 四色图（每象限 16x16 纯色），用于 EXIF 方向断言：TL红 TR蓝 / BL绿 BR黄。
    /// 用 32x32 而非 2x2：JPEG 4:2:0 色度按 16x16 MCU 抽样，纯色象限各占独立 MC 才不会被压缩混色；
    /// 断言时取象限中心 (8,8)/(24,8)/(8,24)/(24,24)。
    static func makeQuadImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 32, height: 32,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CG y 向上：先填上半(TL红 TR蓝)，再下半(BL绿 BR黄)
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 16, width: 16, height: 16))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 16, y: 16, width: 16, height: 16))
        ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        ctx.setFillColor(red: 1, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 16, y: 0, width: 16, height: 16))
        return ctx.makeImage()!
    }
}
