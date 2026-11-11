import XCTest
@testable import PicPin

final class LayoutEngineTests: XCTestCase {
    private func makeItem(_ w: Int, _ h: Int) -> ImageItem {
        let img = TestSupport.makeImage(width: w, height: h, color: (0.5, 0.5, 0.5))
        return ImageItem(id: UUID(), cgImage: img, thumbnail: img, fileName: "\(w)x\(h).png")
    }

    /// CGRect 分量级比较（归一化坐标下 0.5 容差）
    private func assertRect(_ a: CGRect, _ b: CGRect, accuracy: CGFloat = 0.5,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(abs(a.minX - b.minX), accuracy, file: file, line: line)
        XCTAssertLessThan(abs(a.minY - b.minY), accuracy, file: file, line: line)
        XCTAssertLessThan(abs(a.width - b.width), accuracy, file: file, line: line)
        XCTAssertLessThan(abs(a.height - b.height), accuracy, file: file, line: line)
    }

    // 画布：3:4 + base 1000 → 1000 x 1333.33
    func testCanvasRatio() {
        var c = Composition()
        c.items = [makeItem(100, 200)]
        let r = LayoutEngine.layout(c)
        XCTAssertEqual(r.canvasSize.width, 1000, accuracy: 0.001)
        XCTAssertEqual(r.canvasSize.height, 1000 * 4.0 / 3.0, accuracy: 0.001)
    }

    func testVerticalEvenSplitThreeItems() {
        var c = Composition()
        c.items = [makeItem(100, 50), makeItem(100, 50), makeItem(100, 50)]
        let r = LayoutEngine.layout(c)
        let H = 1000 * 4.0 / 3.0
        XCTAssertEqual(r.placements.count, 3)
        assertRect(r.placements[0].destination, CGRect(x: 0, y: 0, width: 1000, height: H / 3))
        XCTAssertEqual(r.placements[1].destination.minY, H / 3, accuracy: 0.5)
        XCTAssertEqual(r.placements[2].destination.minY, H * 2 / 3, accuracy: 0.5)
    }

    func testVerticalWeightsGapMargin() {
        var c = Composition()
        c.items = [makeItem(100, 50), makeItem(100, 50)]
        c.weights = [0.25, 0.75]                      // 归一后不变
        c.gap = 40
        c.margin = 60
        let r = LayoutEngine.layout(c)
        let H = 1000 * 4.0 / 3.0
        let strips = (H - 120) - 40
        assertRect(r.placements[0].destination, CGRect(x: 60, y: 60, width: 880, height: strips * 0.25))
        XCTAssertEqual(r.placements[1].destination.minY, 60 + strips * 0.25 + 40, accuracy: 0.5)
        XCTAssertEqual(r.placements[1].destination.width, 880, accuracy: 0.5)
    }

    // fill：图 100x50（横图），条带 1000 宽。scale = max(10, stripH/50)
    func testVerticalFillStartCenterEnd() {
        var c = Composition()
        c.items = [makeItem(100, 50), makeItem(100, 50), makeItem(100, 50)]
        let H = 1000 * 4.0 / 3.0
        c.direction = .vertical
        c.policies = [
            c.items[0].id: SlicePolicy(mode: .fill, alignment: .start),
            c.items[1].id: SlicePolicy(mode: .fill, alignment: .center),
            c.items[2].id: SlicePolicy(mode: .fill, alignment: .end),
        ]
        let r = LayoutEngine.layout(c)
        let stripH = H / 3                                  // ≈444.4
        // scale = max(10, 8.89) = 10 → 显示 1000x500：x 贴合、y(主轴)溢出 55.6
        // 源保留高 = stripH/10 ≈ 44.4，start→y=0, center→2.78, end→5.56
        let expectedY: [CGFloat] = [0, (50 - stripH / 10) / 2, 50 - stripH / 10]
        for i in 0..<3 {
            let src = try! XCTUnwrap(r.placements[i].sourceRect)
            XCTAssertEqual(src.width, 100, accuracy: 0.5)
            XCTAssertEqual(src.height, stripH / 10, accuracy: 0.5)
            XCTAssertEqual(src.minY, expectedY[i], accuracy: 0.5)
            assertRect(r.placements[i].fittedFrame, r.placements[i].destination)
        }
    }

    // fit：图 100x20，1:1 画布。scale = min(10, 50) = 10 → fitted 1000x200
    //（min 保证恰好一边贴合：此处宽贴合，上下各留 400）
    func testVerticalFitLetterbox() {
        var c = Composition()
        c.items = [makeItem(100, 20)]                      // 5:1 横条图
        c.aspectRatio = RatioPresets.r1x1
        c.policies = [c.items[0].id: SlicePolicy(mode: .fit, alignment: .center)]
        let r = LayoutEngine.layout(c)
        let p = r.placements[0]
        XCTAssertNil(p.sourceRect)
        XCTAssertEqual(p.fittedFrame.width, 1000, accuracy: 0.5)
        XCTAssertEqual(p.fittedFrame.height, 200, accuracy: 0.5)
        XCTAssertEqual(p.fittedFrame.midX, 500, accuracy: 0.5)
        XCTAssertEqual(p.fittedFrame.midY, 500, accuracy: 0.5)
        assertRect(p.destination, CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    func testOversizedGapMarginClampsToZero() {
        var c = Composition()
        c.items = [makeItem(100, 50), makeItem(100, 50)]
        c.gap = 5000                                        // gap+margin 远超画布
        c.margin = 2000
        let r = LayoutEngine.layout(c)
        for p in r.placements {
            XCTAssertGreaterThanOrEqual(p.destination.height, 0)
            XCTAssertFalse(p.destination.height.isNaN)
        }
    }

    func testEmptyItemsReturnsEmptyPlacements() {
        let r = LayoutEngine.layout(Composition())
        XCTAssertTrue(r.placements.isEmpty)
        XCTAssertEqual(r.canvasSize.width, 1000, accuracy: 0.001)
    }
}
