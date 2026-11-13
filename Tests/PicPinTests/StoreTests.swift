import XCTest
import CoreGraphics
@testable import PicPin

@MainActor
final class StoreTests: XCTestCase {
    /// 数组逐元素比较（XCTest accuracy 重载不支持数组）
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

    private func storeWithFiles(_ n: Int) throws -> (CompositionStore, [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 0..<n {
            let url = dir.appendingPathComponent("img\(i).png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, TestSupport.makeImage(width: 100, height: 100, color: (0.3, 0.3, 0.3)), nil)
            CGImageDestinationFinalize(dest)
            urls.append(url)
        }
        return (CompositionStore(), urls)
    }

    func testAddImagesAppendsAndRedistributes() throws {
        let (store, urls) = try storeWithFiles(2)
        store.addImages(from: urls)
        XCTAssertEqual(store.composition.items.count, 2)
        assertWeights(store.composition.normalizedWeights, [0.5, 0.5])
        // 微调后追加：保留旧相对比例，新条均分
        store.setBoundary(0, share: 0.8)                     // n=2 → pairSum=1 → [0.8, 0.2]
        store.addImages(from: [urls[0]])                     // 加第三张
        let w = store.composition.normalizedWeights
        XCTAssertEqual(w.count, 3)
        XCTAssertEqual(w.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(w[0] / w[1], 0.8 / 0.2, accuracy: 1e-9)  // 旧相对比例保持
    }

    func testAddImagesIgnoresNonImages() throws {
        let (store, urls) = try storeWithFiles(1)
        let junk = urls[0].deletingLastPathComponent().appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: junk)
        store.addImages(from: [junk])
        XCTAssertEqual(store.composition.items.count, 0)
        XCTAssertEqual(store.lastIgnoredCount, 1)
        store.addImages(from: urls)
        XCTAssertEqual(store.composition.items.count, 1)
    }

    func testMoveKeepsWeightsAligned() throws {
        let (store, urls) = try storeWithFiles(3)
        store.addImages(from: urls)
        store.setBoundary(0, share: 0.8)                     // n=3 → pairSum=2/3 → [0.533,0.133,0.333]
        let before = store.composition.normalizedWeights
        let id0 = store.composition.items[0].id
        store.move(from: IndexSet(integer: 0), to: 3)        // 移到末尾
        XCTAssertEqual(store.composition.items[2].id, id0)
        let after = store.composition.normalizedWeights
        XCTAssertEqual(after[2], before[0], accuracy: 1e-9)  // 权重跟随图片
    }

    func testRemoveKeepsRelativeAndCleansSelection() throws {
        let (store, urls) = try storeWithFiles(3)
        store.addImages(from: urls)
        store.setBoundary(0, share: 0.8)                     // n=3 → pairSum=2/3 → [0.533,0.133,0.333]
        let removedID = store.composition.items[1].id
        store.composition.policies[removedID] = SlicePolicy(mode: .fit, alignment: .start)
        store.selectedID = removedID
        store.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(store.composition.items.count, 2)
        XCTAssertNil(store.selectedID)
        XCTAssertFalse(store.composition.policies.keys.contains(removedID))  // 策略同步清理
        let w = store.composition.normalizedWeights
        XCTAssertEqual(w.reduce(0, +), 1, accuracy: 1e-9)
        // setBoundary(0,0.8) 在 n=3 时：w=[0.8·⅔, ⅓−0.8·⅔, ⅓]；删中间条后 ratio = 0.8·⅔ ÷ ⅓ = 1.6 精确
        XCTAssertEqual(w[0] / w[1], (0.8 * (2.0 / 3.0)) / (1.0 / 3.0), accuracy: 1e-9)
    }

    func testResetToEven() throws {
        let (store, urls) = try storeWithFiles(3)
        store.addImages(from: urls)
        store.setBoundary(0, share: 0.9)
        store.resetToEven()
        assertWeights(store.composition.normalizedWeights, [1.0/3, 1.0/3, 1.0/3])
    }

    func testResolvedOutputWidthOriginal() throws {
        let (store, urls) = try storeWithFiles(1)
        XCTAssertEqual(
            ExportWidthOption.allOptions,
            [.original, .fixed(1080), .fixed(1440), .fixed(2048),
             .percent(25), .percent(50), .percent(75), .percent(100)]
        )
        XCTAssertEqual(
            ExportWidthOption.allOptions.map(\.label),
            ["原始", "1080", "1440", "2048", "25%", "50%", "75%", "100%"]
        )
        XCTAssertEqual(store.exportWidthOption, .original)    // 默认原始宽

        store.addImages(from: urls)                           // 100px 宽图
        XCTAssertEqual(store.resolvedOutputWidth, 100)

        for pct in [25, 50, 75, 100] {
            store.exportWidthOption = .percent(pct)
            XCTAssertEqual(store.resolvedOutputWidth, pct)
        }

        for w in [1080, 1440, 2048] {
            store.exportWidthOption = .fixed(w)
            XCTAssertEqual(store.resolvedOutputWidth, w)
        }
    }
}
