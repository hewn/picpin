import XCTest
@testable import PicPin

final class CompositionTests: XCTestCase {
    /// XCTest 的 accuracy 重载不支持数组，逐元素比较（计划缺陷修正，见 ledger Task 2 ruling）
    private func assertWeights(_ actual: [Double], _ expected: [Double],
                               accuracy: Double = 1e-9,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual.count == expected.count else { return }
        for i in expected.indices {
            XCTAssertLessThan(abs(actual[i] - expected[i]), accuracy,
                              "index \(i): \(actual[i]) vs \(expected[i])",
                              file: file, line: line)
        }
    }

    private func makeItems(_ n: Int) -> [ImageItem] {
        (0..<n).map { i in
            let img = TestSupport.makeImage(width: 100, height: 50, color: (1, 0, 0))
            return ImageItem(id: UUID(), cgImage: img, thumbnail: img, fileName: "img\(i).png")
        }
    }

    func testNormalizedWeightsEvenWhenEmptyOrMismatched() {
        var c = Composition()
        c.items = makeItems(3)
        c.weights = []                                  // 数量不匹配 → 均分
        assertWeights(c.normalizedWeights, [1.0/3, 1.0/3, 1.0/3])
        c.weights = [0.5]                               // 长度不齐 → 均分
        XCTAssertEqual(c.normalizedWeights.count, 3)
        XCTAssertEqual(c.normalizedWeights.reduce(0, +), 1, accuracy: 1e-9)
    }

    func testNormalizedWeightsScalesAndClamps() {
        var c = Composition()
        c.items = makeItems(3)
        c.weights = [2, 1, 1]                           // 归一化 → [0.5, 0.25, 0.25]
        assertWeights(c.normalizedWeights, [0.5, 0.25, 0.25])
        c.weights = [0.01, 0.6, 0.39]                   // 0.01 < 0.05 → clamp 并重分配
        let w = c.normalizedWeights
        XCTAssertGreaterThanOrEqual(w[0], Composition.minWeight - 1e-9)
        XCTAssertEqual(w.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(w[1], 0.5)                 // 扣减量来自其他条
    }

    func testTooManyItemsForMinWeightFallsBackToEven() {
        var c = Composition()
        c.items = makeItems(21)                          // 21 * 0.05 > 1 → 无法全部满足
        c.weights = Array(repeating: 0.001, count: 21)
        assertWeights(c.normalizedWeights, Array(repeating: 1.0/21, count: 21))
    }

    func testSetBoundaryRedistributesPairOnly() {
        var c = Composition()
        c.items = makeItems(3)
        c.weights = [0.2, 0.3, 0.5]
        c.setBoundary(0, share: 0.5)                     // 前两条总和 0.5 内部五五开
        assertWeights(c.normalizedWeights, [0.25, 0.25, 0.5])
    }

    func testSetBoundaryClampsToMinWeight() {
        var c = Composition()
        c.items = makeItems(2)
        c.weights = [0.5, 0.5]
        c.setBoundary(0, share: -1)                      // 越界 → 第一条 clamp 到 0.05
        XCTAssertEqual(c.normalizedWeights[0], Composition.minWeight, accuracy: 1e-9)
        XCTAssertEqual(c.normalizedWeights.reduce(0, +), 1, accuracy: 1e-9)
        c.setBoundary(0, share: 2)                       // 反向越界 → 第二条 clamp
        XCTAssertEqual(c.normalizedWeights[1], Composition.minWeight, accuracy: 1e-9)
    }

    func testPolicyDefaultIsFillCenter() {
        let c = Composition()
        XCTAssertEqual(c.policy(for: UUID()), SlicePolicy(mode: .fill, alignment: .center))
    }
}
