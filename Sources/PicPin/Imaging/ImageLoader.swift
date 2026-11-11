import CoreGraphics
import ImageIO
import Foundation

enum ImageLoader {
    static let thumbnailMaxPixel = 1200

    static func loadItem(from url: URL) -> ImageItem? {
        let srcOptions = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        guard CGImageSourceGetCount(src) > 0 else { return nil }
        guard let raw = CGImageSourceCreateImageAtIndex(src, 0, srcOptions) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let upright = normalize(raw, exifOrientation: orientation)
        let thumb = makeThumbnail(src) ?? upright
        return ImageItem(id: UUID(), cgImage: upright, thumbnail: thumb,
                         fileName: url.lastPathComponent)
    }

    /// EXIF 规范化。原子变换（CG y 向上，已推导验证）：
    /// rotate90CW  = translate(0, w) + rotate(-π/2)，输出画布 (h, w)
    /// rotate90CCW = translate(h, 0) + rotate(+π/2)，输出画布 (h, w)
    /// flipH = translate(w, 0) + scale(-1, 1)；flipV = translate(0, h) + scale(1, -1)
    /// EXIF: 2=flipH 3=rot180 4=flipV 5=flipH→CCW 6=CW 7=flipH→CW 8=CCW
    static func normalize(_ image: CGImage, exifOrientation o: UInt32) -> CGImage {
        guard (2...8).contains(o) else { return image }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let swapped = (5...8).contains(o)
        let cw = swapped ? h : w, ch = swapped ? w : h
        guard let ctx = CGContext(data: nil, width: Int(cw), height: Int(ch),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        switch o {
        case 2:
            ctx.translateBy(x: w, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 3:
            ctx.translateBy(x: w, y: h); ctx.rotate(by: .pi)
        case 4:
            ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)
        case 5:
            ctx.translateBy(x: h, y: 0); ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: w, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 6:
            ctx.translateBy(x: 0, y: w); ctx.rotate(by: -.pi / 2)
        case 7:
            ctx.translateBy(x: 0, y: w); ctx.rotate(by: -.pi / 2)
            ctx.translateBy(x: w, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 8:
            ctx.translateBy(x: h, y: 0); ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func makeThumbnail(_ src: CGImageSource) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // 自动应用 EXIF 方向
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
