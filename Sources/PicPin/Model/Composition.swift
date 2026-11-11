import CoreGraphics
import Foundation

struct Composition {
    var direction: StitchDirection = .vertical
    var aspectRatio: AspectRatio = RatioPresets.default
    var items: [ImageItem] = []
    var weights: [Double] = []                  // 与 items 等长且全部 > 0 时生效，否则均分
    var policies: [UUID: SlicePolicy] = [:]
    var gap: Double = 0                          // 相对值，单位 = LayoutEngine.base
    var margin: Double = 0
    var backgroundColor: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    static let minWeight = 0.05
}

extension Composition {
    var count: Int { items.count }

    func policy(for id: UUID) -> SlicePolicy {
        policies[id] ?? SlicePolicy()
    }

    /// 归一化权重：数量不匹配/非法时均分；每条 ≥ minWeight；总和恒为 1
    var normalizedWeights: [Double] {
        let n = items.count
        guard n > 0 else { return [] }
        let even = Array(repeating: 1.0 / Double(n), count: n)
        guard weights.count == n, weights.allSatisfy({ $0 > 0 }) else { return even }
        guard Double(n) * Self.minWeight <= 1.0 else { return even }   // 无法全部满足下限
        let sum = weights.reduce(0, +)
        var w = weights.map { $0 / sum }
        for _ in 0..<n {                                              // 迭代分摊 clamp 扣减
            let under = w.filter { $0 < Self.minWeight }
            if under.isEmpty { break }
            let deficit = under.reduce(0.0) { $0 + (Self.minWeight - $1) }
            let overIdx = w.indices.filter { w[$0] >= Self.minWeight }
            let overSum = overIdx.reduce(0.0) { $0 + w[$1] }
            guard overSum > 0 else { break }
            for i in w.indices {
                if w[i] < Self.minWeight { w[i] = Self.minWeight }
                else { w[i] -= deficit * (w[i] / overSum) }
            }
        }
        let s = w.reduce(0, +)
        return w.map { $0 / s }
    }

    /// 拖动第 index 与 index+1 条之间边界：share ∈ [0,1] 表示第一条在本对总占比中的份额
    mutating func setBoundary(_ index: Int, share: Double) {
        let n = items.count
        guard n > 1, index >= 0, index < n - 1 else { return }
        var w = normalizedWeights
        let i = index, j = index + 1
        let pairSum = w[i] + w[j]                       // 本对总量不变，其他条不动
        let lo = Self.minWeight
        guard pairSum >= 2 * lo else { return }          // N > 10 时保护：保持总和恒定优先
        let wi = min(max(share * pairSum, lo), pairSum - lo)
        w[i] = wi
        w[j] = pairSum - wi
        weights = w
    }
}
