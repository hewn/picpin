import CoreGraphics
import Foundation

struct ImageItem: Identifiable {
    let id: UUID
    let cgImage: CGImage        // 已按 EXIF 方向规范化的原图
    let thumbnail: CGImage      // 预览用缩略图（最长边 ≤ 1200）
    let fileName: String
    var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
}
