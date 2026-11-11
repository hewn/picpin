import CoreGraphics
import Foundation

struct ImageItem: Identifiable {
    let id: UUID
    let cgImage: CGImage        // 已按 EXIF 方向规范化的原图
    let thumbnail: CGImage      // 预览用缩略图（最长边 ≤ 1200）
    let fileName: String
    var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }

    /// 将原图像素坐标的裁剪 rect 映射到缩略图像素坐标（逐轴缩放）。
    /// LayoutEngine 的 sourceRect 是原图像素单位；预览用缩略图渲染时必须换算，
    /// 否则裁剪区域错误（终审 Critical 2）。
    func thumbnailSourceRect(from source: CGRect) -> CGRect {
        let sx = CGFloat(thumbnail.width) / CGFloat(cgImage.width)
        let sy = CGFloat(thumbnail.height) / CGFloat(cgImage.height)
        return CGRect(x: source.minX * sx, y: source.minY * sy,
                      width: source.width * sx, height: source.height * sy)
    }
}
