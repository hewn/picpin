import CoreGraphics
import ImageIO
import Foundation

enum ImageLoader {
    static let thumbnailMaxPixel = 1200
    static let listIconMaxPixel = 120

    static func loadItem(from url: URL) -> ImageItem? {
        let srcOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }
        guard CGImageSourceGetCount(src) > 0 else { return nil }
        guard let raw = CGImageSourceCreateImageAtIndex(src, 0, srcOptions as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let upright = normalize(raw, exifOrientation: orientation)
        let thumb: CGImage
        if max(upright.width, upright.height) <= thumbnailMaxPixel {
            thumb = predecode(upright)
        } else {
            thumb = makeThumbnail(src, maxPixel: thumbnailMaxPixel).map(predecode) ?? upright
        }
        let icon: CGImage
        if max(thumb.width, thumb.height) <= listIconMaxPixel {
            icon = thumb
        } else {
            icon = makeThumbnail(src, maxPixel: listIconMaxPixel).map(predecode) ?? thumb
        }
        return ImageItem(id: UUID(), cgImage: upright, thumbnail: thumb, listIcon: icon,
                         fileName: url.lastPathComponent)
    }

    /// 强制在后台线程将 CGImage 解压光栅化为紧致的 8-bit Premultiplied RGBA 位图，避免主线程 SwiftUI 渲染时惰性解码卡顿
    private static func predecode(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
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

    static func makeThumbnail(_ src: CGImageSource, maxPixel: Int = thumbnailMaxPixel) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // 自动应用 EXIF 方向
            kCGImageSourceShouldCacheImmediately: true,           // 后台立即解码
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
