import CoreGraphics
import SwiftUI

enum StitchDirection: String, CaseIterable, Identifiable {
    case vertical, horizontal
    var id: String { rawValue }
    var label: String { self == .vertical ? "垂直拼接" : "水平拼接" }
}

enum FitMode: String, CaseIterable, Identifiable {
    case fill, fit, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fill: return "等比撑满"
        case .fit: return "完整留白"
        case .custom: return "自定义"
        }
    }
}

enum CropAlignment: String, CaseIterable, Identifiable {
    case start, center, end
    var id: String { rawValue }
    var defaultOffset: Double {
        switch self {
        case .start: return 0.0
        case .center: return 0.5
        case .end: return 1.0
        }
    }
    func label(for direction: StitchDirection) -> String {
        switch (self, direction) {
        case (.start, .vertical): return "保留顶部"
        case (.center, .vertical): return "保留中间"
        case (.end, .vertical): return "保留底部"
        case (.start, .horizontal): return "保留左侧"
        case (.center, .horizontal): return "保留中间"
        case (.end, .horizontal): return "保留右侧"
        }
    }
}

struct SlicePolicy: Equatable {
    var mode: FitMode = .fill
    var alignment: CropAlignment = .center
    /// 自定义缩放倍率（1.0 = 100%，以条带内完整显示尺寸为 100% 基准；支持任意正数倍缩放）
    var customScale: Double = 1.0
    /// 归一化位置偏移 [0, 1]（0 = 顶/左，0.5 = 居中，1 = 底/右）。
    /// nil 表示未手动微调，由 LayoutEngine 按 alignment 与方向计算。
    var customOffsetX: Double? = nil
    var customOffsetY: Double? = nil

    var hasCustomOffset: Bool {
        customOffsetX != nil || customOffsetY != nil
    }
}

struct AspectRatio: Identifiable, Hashable {
    let id: String
    let w: Double
    let h: Double
    var value: Double { w / h }

    static func custom(_ w: Double, _ h: Double) -> AspectRatio {
        func f(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
        return AspectRatio(id: "自定义 \(f(w)):\(f(h))", w: w, h: h)
    }
}

enum RatioPresets {
    static let r3x4 = AspectRatio(id: "3:4", w: 3, h: 4)
    static let r9x16 = AspectRatio(id: "9:16", w: 9, h: 16)
    static let r1x1 = AspectRatio(id: "1:1", w: 1, h: 1)
    static let r4x3 = AspectRatio(id: "4:3", w: 4, h: 3)
    static let r16x9 = AspectRatio(id: "16:9", w: 16, h: 9)
    static let r235x1 = AspectRatio(id: "2.35:1", w: 2.35, h: 1)
    static let all: [AspectRatio] = [r3x4, r9x16, r1x1, r4x3, r16x9, r235x1]
    static let `default` = r3x4
}
