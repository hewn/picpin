import XCTest
import SwiftUI
@testable import PicPin

/// 终审 Critical 修复的回归测试：
/// 1. 条带内局部坐标 localFittedFrame（修复预览错位）
/// 2. 原图像素坐标 → 缩略图像素坐标映射（修复预览裁剪错误）
/// 3. ImageRenderer 端到端：多条带预览必须按顺序出现在画布上/下半
@MainActor
final class PreviewMappingTests: XCTestCase {
    private func makeItem(_ w: Int, _ h: Int, _ c: (CGFloat, CGFloat, CGFloat),
                          thumbW: Int? = nil, thumbH: Int? = nil) -> ImageItem {
        let img = TestSupport.makeImage(width: w, height: h, color: c)
        let tw = thumbW ?? w, th = thumbH ?? h
        let thumb = TestSupport.makeImage(width: tw, height: th, color: c)
        return ImageItem(id: UUID(), cgImage: img, thumbnail: thumb, fileName: "t.png")
    }

    // MARK: - localFittedFrame

    func testLocalFittedFrameFillEqualsDestination() {
        var c = Composition()
        c.items = [makeItem(100, 50, (1, 0, 0))]
        c.aspectRatio = RatioPresets.r1x1
        let p = LayoutEngine.layout(c).placements[0]   // fill：fitted == destination
        let local = p.localFittedFrame
        XCTAssertEqual(local.minX, 0, accuracy: 0.5)
        XCTAssertEqual(local.minY, 0, accuracy: 0.5)
        XCTAssertEqual(local.width, p.destination.width, accuracy: 0.5)
        XCTAssertEqual(local.height, p.destination.height, accuracy: 0.5)
    }

    func testLocalFittedFrameFitIsCenteredInsideStrip() {
        var c = Composition()
        c.items = [makeItem(100, 20, (1, 0, 0))]      // 5:1 横条 → fit 后 1000x200 居中
        c.aspectRatio = RatioPresets.r1x1
        c.policies = [c.items[0].id: SlicePolicy(mode: .fit, alignment: .center)]
        let p = LayoutEngine.layout(c).placements[0]
        let local = p.localFittedFrame
        XCTAssertEqual(local.minY, 400, accuracy: 0.5) // (1000-200)/2
        XCTAssertEqual(local.width, 1000, accuracy: 0.5)
        XCTAssertEqual(local.height, 200, accuracy: 0.5)
    }

    // MARK: - thumbnailSourceRect

    func testThumbnailSourceRectScalesByAxis() {
        // 原图 3000x2000，缩略图 1200x800（等比 0.4）
        let item = makeItem(3000, 2000, (0, 0, 0), thumbW: 1200, thumbH: 800)
        let mapped = item.thumbnailSourceRect(from: CGRect(x: 750, y: 500, width: 1500, height: 1000))
        XCTAssertEqual(mapped.minX, 300, accuracy: 0.5)
        XCTAssertEqual(mapped.minY, 200, accuracy: 0.5)   // 500 * 0.4
        XCTAssertEqual(mapped.width, 600, accuracy: 0.5)
        XCTAssertEqual(mapped.height, 400, accuracy: 0.5)
    }

    func testThumbnailSourceRectIdentityWhenSameSize() {
        let item = makeItem(100, 100, (0, 0, 0))
        let src = CGRect(x: 10, y: 20, width: 50, height: 30)
        XCTAssertEqual(item.thumbnailSourceRect(from: src), src)
    }

    // MARK: - 端到端预览（ImageRenderer）

    private func rgba(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let data = img.dataProvider!.data! as Data
        let i = y * img.bytesPerRow + x * img.bitsPerPixel / 8
        return (data[i], data[i+1], data[i+2])
    }
    private func isRed(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.0 > 200 && p.1 < 80 && p.2 < 80 }
    private func isBlue(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.2 > 200 && p.0 < 80 && p.1 < 80 }

    /// 两条带（红/蓝）1:1 画布：画布内容上半必须出现红、下半必须出现蓝。
    /// 修复前（嵌套 .position 用画布坐标）：条带2 被放到画布外 → 下半无蓝 → FAIL。
    /// 注：ScrollView 在 ImageRenderer 中不渲染，故直渲 CanvasContentView。
    func testPreviewRendersStripsInCanvasOrder() throws {
        let store = CompositionStore()
        var c = store.composition
        c.aspectRatio = RatioPresets.r1x1
        let red = makeItem(200, 100, (1, 0, 0))
        let blue = makeItem(200, 100, (0, 0, 1))
        c.items = [red, blue]
        store.composition = c

        let layout = LayoutEngine.layout(c)
        let scale: CGFloat = 0.3
        var dragBase: (pairSum: Double, share: Double)? = nil
        let renderer = ImageRenderer(content: CanvasContentView(
            store: store, layout: layout, scale: scale, dragBase: Binding(
                get: { dragBase }, set: { dragBase = $0 }))
            .frame(width: layout.canvasSize.width * scale,
                   height: layout.canvasSize.height * scale))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer 未产出图像")
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 300)

        var redInTop = false, blueInBottom = false
        let midY = image.height / 2
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let p = rgba(image, x, y)
                if y < midY, isRed(p) { redInTop = true }
                if y >= midY, isBlue(p) { blueInBottom = true }
            }
        }
        XCTAssertTrue(redInTop, "上半区应出现红色条带")
        XCTAssertTrue(blueInBottom, "下半区应出现蓝色条带（修复前条带2被错位到画布外）")
    }
}
