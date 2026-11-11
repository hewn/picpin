import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageExporter {
    enum Format: String, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPEG"
        var id: String { rawValue }
    }

    static func encode(_ image: CGImage, format: Format) -> Data? {
        let ut: UTType = format == .png ? .png : .jpeg
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, ut.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.92]
            : [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// 同时写 PNG 与 TIFF，最大化粘贴兼容性（微信/小红书/文档）
    static func copyToClipboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        var payloads: [(Data, NSPasteboard.PasteboardType)] = []
        if let png = encode(image, format: .png) {
            payloads.append((png, .png))
        }
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            payloads.append((tiff, .tiff))
        }
        guard let first = payloads.first else { return }
        pb.setData(first.0, forType: first.1)
        for (d, t) in payloads.dropFirst() { pb.setData(d, forType: t) }
    }
}
