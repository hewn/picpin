import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PicPin

final class ImageLoaderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicPinTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 写出带 EXIF orientation 的 32x32 四色 JPEG（采样取象限中心：TL(8,8) TR(24,8) BL(8,24) BR(24,24)）
    private func writeQuadJPEG(orientation: UInt32, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(dest, TestSupport.makeQuadImage(), props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// 读 CGImage 某像素（topLeft 坐标，data 第一行 = 图像顶部）
    private func rgba(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let data = img.dataProvider!.data! as Data
        let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
        let i = y * bpr + x * bpp
        return (data[i], data[i+1], data[i+2])
    }

    private func isRed(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.0 > 200 && p.1 < 80 && p.2 < 80 }
    private func isBlue(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.2 > 200 && p.0 < 80 && p.1 < 80 }
    private func isGreen(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.1 > 200 && p.0 < 80 && p.2 < 80 }
    private func isYellow(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.0 > 200 && p.1 > 200 && p.2 < 80 }

    // raw 四色（orientation 1）：TL红 TR蓝 / BL绿 BR黄
    func testOrientation1Identity() throws {
        let url = try writeQuadJPEG(orientation: 1, name: "o1.jpg")
        let item = ImageLoader.loadItem(from: url)
        XCTAssertNotNil(item)
        XCTAssertTrue(isRed(rgba(item!.cgImage, 8, 8)), "TL 应为红")
        XCTAssertTrue(isBlue(rgba(item!.cgImage, 24, 8)), "TR 应为蓝")
    }

    // 期望角颜色表（四色 raw：TL红 TR蓝 / BL绿 BR黄；归一化后的 upright 角）
    // o=3(180°):   TL=黄 TR=绿 / BL=蓝 BR=红
    // o=6(90°CW):  TL=绿 TR=红 / BL=黄 BR=蓝
    // o=8(90°CCW): TL=蓝 TR=黄 / BL=红 BR=绿
    // o=5(transpose): TL=红 TR=绿 / BL=蓝 BR=黄
    func testOrientation3Rot180() throws {
        let url = try writeQuadJPEG(orientation: 3, name: "o3.jpg")
        let img = ImageLoader.loadItem(from: url)!.cgImage
        XCTAssertTrue(isYellow(rgba(img, 8, 8)));   XCTAssertTrue(isGreen(rgba(img, 24, 8)))
        XCTAssertTrue(isBlue(rgba(img, 8, 24)));    XCTAssertTrue(isRed(rgba(img, 24, 24)))
    }

    func testOrientation6Rot90CW() throws {
        let url = try writeQuadJPEG(orientation: 6, name: "o6.jpg")
        let img = ImageLoader.loadItem(from: url)!.cgImage
        XCTAssertTrue(isGreen(rgba(img, 8, 8)));    XCTAssertTrue(isRed(rgba(img, 24, 8)))
        XCTAssertTrue(isYellow(rgba(img, 8, 24)));  XCTAssertTrue(isBlue(rgba(img, 24, 24)))
    }

    func testOrientation8Rot90CCW() throws {
        let url = try writeQuadJPEG(orientation: 8, name: "o8.jpg")
        let img = ImageLoader.loadItem(from: url)!.cgImage
        XCTAssertTrue(isBlue(rgba(img, 8, 8)));     XCTAssertTrue(isYellow(rgba(img, 24, 8)))
        XCTAssertTrue(isRed(rgba(img, 8, 24)));     XCTAssertTrue(isGreen(rgba(img, 24, 24)))
    }

    func testOrientation5Transpose() throws {
        let url = try writeQuadJPEG(orientation: 5, name: "o5.jpg")
        let img = ImageLoader.loadItem(from: url)!.cgImage
        XCTAssertTrue(isRed(rgba(img, 8, 8)));      XCTAssertTrue(isGreen(rgba(img, 24, 8)))
        XCTAssertTrue(isBlue(rgba(img, 8, 24)));    XCTAssertTrue(isYellow(rgba(img, 24, 24)))
    }

    func testThumbnailIsDownsampled() throws {
        // 造 800x600 图
        let url = dir.appendingPathComponent("big.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        let big = TestSupport.makeImage(width: 800, height: 600, color: (0.2, 0.4, 0.6))
        CGImageDestinationAddImage(dest, big, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let item = ImageLoader.loadItem(from: url)!
        XCTAssertEqual(item.cgImage.width, 800)                 // 原图保真
        XCTAssertEqual(item.thumbnail.width, 800)               // ≤1200 不降采样
        // 造 3000x2000 图 → 缩略图最长边 1200
        let url2 = dir.appendingPathComponent("huge.png")
        let dest2 = CGImageDestinationCreateWithURL(url2 as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest2, TestSupport.makeImage(width: 3000, height: 2000, color: (0.1, 0.1, 0.1)), nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest2))
        let item2 = ImageLoader.loadItem(from: url2)!
        XCTAssertEqual(item2.cgImage.width, 3000)               // 原图保真
        XCTAssertLessThan(abs(item2.thumbnail.width - 1200), 5) // 降采样到最长边 1200
    }

    func testLoadInvalidFileReturnsNil() {
        let url = dir.appendingPathComponent("junk.bin")
        try! Data("not an image".utf8).write(to: url)
        XCTAssertNil(ImageLoader.loadItem(from: url))
    }
}
