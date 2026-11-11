import XCTest
import CoreGraphics
@testable import PicPin

final class RendererTests: XCTestCase {
    private func makeItem(_ w: Int, _ h: Int, _ c: (CGFloat, CGFloat, CGFloat)) -> ImageItem {
        let img = TestSupport.makeImage(width: w, height: h, color: c)
        return ImageItem(id: UUID(), cgImage: img, thumbnail: img, fileName: "t.png")
    }

    /// topLeft 坐标读像素（CG bitmap data 第一行 = 图像顶部）
    private func rgba(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let data = img.dataProvider!.data! as Data
        let i = y * img.bytesPerRow + x * img.bitsPerPixel / 8
        return (data[i], data[i+1], data[i+2])
    }

    private func isColor(_ p: (UInt8, UInt8, UInt8), _ c: (CGFloat, CGFloat, CGFloat), tol: UInt8 = 30) -> Bool {
        abs(Int(p.0) - Int(c.0 * 255)) < Int(tol) &&
        abs(Int(p.1) - Int(c.1 * 255)) < Int(tol) &&
        abs(Int(p.2) - Int(c.2 * 255)) < Int(tol)
    }

    // 两张 2:1 纯色图（红/蓝），1:1 画布无 gap/margin，fill center → 上下两半各半
    func testRenderSizeAndColors() {
        var c = Composition()
        c.aspectRatio = RatioPresets.r1x1
        c.items = [makeItem(200, 100, (1, 0, 0)), makeItem(200, 100, (0, 0, 1))]
        guard let out = CompositionRenderer.render(c, outputWidth: 600) else {
            return XCTFail("渲染失败")
        }
        XCTAssertEqual(out.width, 600)
        XCTAssertEqual(out.height, 600)
        XCTAssertTrue(isColor(rgba(out, 300, 150), (1, 0, 0)), "上半中心应为红")
        XCTAssertTrue(isColor(rgba(out, 300, 450), (0, 0, 1)), "下半中心应为蓝")
    }

    func testRenderGapShowsBackground() {
        var c = Composition()
        c.aspectRatio = RatioPresets.r1x1
        c.items = [makeItem(200, 100, (1, 0, 0)), makeItem(200, 100, (0, 0, 1))]
        c.gap = 100                                          // base=1000 的 10%
        c.backgroundColor = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        guard let out = CompositionRenderer.render(c, outputWidth: 600) else {
            return XCTFail("渲染失败")
        }
        // gap 在归一化 y=[450,550]，输出 600px → 中线 (300,300) 应为背景绿
        XCTAssertTrue(isColor(rgba(out, 300, 300), (0, 1, 0)), "中线 gap 应为背景绿")
    }

    func testRenderMarginShowsBackground() {
        var c = Composition()
        c.aspectRatio = RatioPresets.r1x1
        c.items = [makeItem(200, 100, (1, 0, 0))]
        c.margin = 100
        c.backgroundColor = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        guard let out = CompositionRenderer.render(c, outputWidth: 600) else {
            return XCTFail("渲染失败")
        }
        XCTAssertTrue(isColor(rgba(out, 300, 5), (0, 1, 0)), "画布顶部应露背景绿")
    }

    func testRenderFitLetterboxBackground() {
        var c = Composition()
        c.aspectRatio = RatioPresets.r1x1
        c.items = [makeItem(100, 20, (1, 0, 0))]             // 5:1 横条
        c.policies = [c.items[0].id: SlicePolicy(mode: .fit, alignment: .center)]
        c.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let out = CompositionRenderer.render(c, outputWidth: 400) else {
            return XCTFail("渲染失败")
        }
        // fit: 归一 scale=min(10,50)=10 → fitted 1000x200；输出 400px 红条占 y=[160,240]
        XCTAssertTrue(isColor(rgba(out, 200, 200), (1, 0, 0)), "红条中心 (y=200) 应为红")
        XCTAssertTrue(isColor(rgba(out, 200, 100), (0, 0, 0)), "红条上方 (y=100) 应为黑背景")
    }

    func testEncodePNGAndJPEGAndHEIC() throws {
        let img = TestSupport.makeImage(width: 64, height: 64, color: (0.5, 0.5, 0.5))
        let png = try XCTUnwrap(ImageExporter.encode(img, format: .png))
        XCTAssertEqual(png.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let jpeg = try XCTUnwrap(ImageExporter.encode(img, format: .jpeg))
        XCTAssertGreaterThan(jpeg.count, 100)
        let heic = try XCTUnwrap(ImageExporter.encode(img, format: .heic))
        XCTAssertGreaterThan(heic.count, 100)
        XCTAssertEqual(ImageExporter.Format.heic.fileExtension, "heic")
    }
}
