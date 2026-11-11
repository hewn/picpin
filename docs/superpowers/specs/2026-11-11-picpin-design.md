# PicPin 设计文档

日期：2026-11-11
状态：已与用户逐节确认

## 1. 产品概述

PicPin 是一个原生 Mac 应用：从 Finder 拖入多张图片，垂直或水平拼接成一张图，并可指定目标输出比例。当目标比例与自然拼接结果不一致时，不做一刀切裁剪，而是**逐张控制子图的处理策略**（等比放大撑满并选择保留顶/中/底，或完整显示留白）。

**主要用途**（已确认）：
- 小红书笔记图（竖版 3:4、9:16 为主）
- 通用长图拼接（对话截图、网页截图等，比例灵活选）

**分发**：先自用，本机 Xcode 直接 build & run，不做签名/公证；后续需要分发再补。

**成功标准**：拖入 → 选方向/比例 → 逐图调策略 → 导出或复制到剪贴板，全程顺畅；导出结果与预览所见一致。

## 2. 核心交互模型（已确认）

1. **空间分配**：目标比例生成固定画布，N 张图按顺序**均分条带**（垂直拼接时为等高横条带，水平拼接时为等宽竖条带）；**可拖动条带边界手动微调**每张图的空间占比。
2. **逐图策略**：每张子图独立选择，两个维度：
   - **FitMode**：
     - `fill` —— 等比放大至撑满所在条带，溢出部分裁掉（即"等比放大"）
     - `fit` —— 等比缩小完整放进条带，周围留背景色
   - **CropAlignment**：`start` / `center` / `end`
     - 垂直拼接时映射为保留**顶/中/底**；水平拼接时映射为保留**左/中/右**
   - 默认 `(fill, .center)`
3. **条带占比约束**：单条最小 5%，防止拖没；weights 自动归一化。

## 3. 架构（方案 A，已确认：共享组合模型 + 双渲染器）

```
PicPin/
├── App/            # PicPinApp 入口、MainWindow 三栏布局
├── Model/          # Composition、ImageItem、策略枚举
├── Engine/         # LayoutEngine 纯函数布局、RatioPresets
├── Views/          # DropZone、CanvasPreview、边界手柄、检查器
├── Export/         # CompositionRenderer(CG)、ImageExporter(ImageIO)、剪贴板
└── Tests/          # LayoutEngine 与渲染器单测
```

数据流：拖入图片 → `Composition` 模型 → `LayoutEngine`（纯函数）→ { SwiftUI 预览， CG 导出 }。

- **单一事实来源**：`Composition` 是唯一状态；预览与导出共享同一份 `LayoutEngine` 几何结果，只是"贴图"执行者不同（SwiftUI vs Core Graphics），保证所见即所得。
- `LayoutEngine` 输出归一化几何（以基准宽为单位），预览与导出各自乘像素密度。

## 4. 数据模型

```swift
enum StitchDirection: String, CaseIterable, Codable {
    case vertical, horizontal
}

enum FitMode: String, Codable { case fill, fit }
enum CropAlignment: String, Codable { case start, center, end }

struct ImageItem: Identifiable {
    let id: UUID
    let cgImage: CGImage          // 加载时已做 EXIF 方向规范化
    let thumbnail: CGImage        // 预览用降采样缩略图
    let fileName: String
    let pixelSize: CGSize         // 像素尺寸；不用 NSImage.size，避开 DPI 坑
}

struct AspectRatio: Identifiable, Hashable {
    let id: String                // "3:4" 等
    let widthRatio: Double
    let heightRatio: Double
    var value: Double { widthRatio / heightRatio }
    // 预设见 §6；自定义由用户输入 w:h 生成
}

struct Composition {
    var direction: StitchDirection = .vertical
    var aspectRatio: AspectRatio = RatioPresets.r3x4
    var items: [ImageItem] = []           // 顺序即拼接顺序
    var weights: [Double] = []            // 与 items 对齐；空/不齐时按均分处理
    var policies: [UUID: SlicePolicy] = [:]  // 缺省 (fill, .center)
    var gap: Double = 0                   // 图间距，以基准宽 base 为单位的相对值（预览/导出等比缩放）
    var margin: Double = 0                // 外边距，同上
    var backgroundColor: SwiftUI.Color = .white
}

struct SlicePolicy { var mode: FitMode; var alignment: CropAlignment }
```

不变量与同步规则：删除图片时同步删除对应 weight 与 policy；weights 始终归一化为和 1（拖动边界时增量写入并重新归一化）。

## 5. LayoutEngine 布局算法（纯函数，单测重点）

输入：`Composition` + 基准宽度 `base`（如 1000 单位）。
输出：

```swift
struct SlicePlacement {
    let itemID: UUID
    let destination: CGRect     // 归一化画布坐标中的目标 frame
    let sourceRect: CGRect?     // 源图裁剪区域（像素坐标）；fit 全图时为 nil = 整图
    let fittedFrame: CGRect     // fill: ==destination；fit: 条带内实际图像 frame（周围留白）
}
struct LayoutResult {
    let canvasSize: CGSize      // 归一化画布尺寸（宽 = base）
    let placements: [SlicePlacement]
}
```

以垂直拼接为例（水平对称）：

1. 画布宽 `W = base`，高 `H = base / ratio.value`。
2. 内容区 = 画布内缩 margin，高度再减去 `(N-1) * gap`。
3. 条带 i 高度 = `内容高 * weight_i`（weights 缺失或不齐时按均分）。
4. 条带内几何：
   - **fill**：`scale = max(stripW/imgW, stripH/imgH)`，等比放大覆盖条带，按 alignment 裁掉溢出维度（垂直拼接时裁上下：start 保留顶、end 保留底），反算源图裁剪 rect。
   - **fit**：`scale = min(stripW/imgW, stripH/imgH)`，居中放置，`fittedFrame` 缩小、四周露背景。
5. gap 与 margin 区域填背景色。

## 6. 比例预设（已确认，竖版优先排序）

| 预设 | 用途 |
|------|------|
| 3:4 | 小红书竖版首图（默认值） |
| 9:16 | 小红书/竖屏全屏 |
| 1:1 | 方图 |
| 4:3 | 通用横版 |
| 16:9 | 通用宽屏/公众号 |
| 2.35:1 | 电影宽幅/公众号封面 |
| 自定义 | 用户输入 w:h |

## 7. UI 与交互（三栏，已确认）

- **左栏·图片列表**：缩略图 + 序号 + 删除按钮；拖动排序（`List` + `onMove`）；继续拖入即追加到尾部。
- **中央·预览画布**：
  - 空态："拖图片到这里"提示 + 拖放热区；
  - 有图：实时预览（读缩略图渲染）；条带间**边界手柄**（细线，hover 放大抓取区），拖动更新相邻两张图的 weights；点选条带高亮并联动右栏。
- **右栏·检查器**：
  - 方向（垂直/水平）
  - 目标比例（预设 Chips + 自定义 w:h）
  - 选中图的策略：FitMode（撑满/完整显示）+ CropAlignment（按方向显示 顶/中/底 或 左/中/右）
  - 全局：间距、边距、背景色（ColorPicker）
  - "重置为均分"按钮
- **底部操作条**：导出按钮（保存文件：PNG/JPEG、宽度 1080/1242/1440/2048/原始最大宽度）+ **复制到剪贴板**按钮。

拖放：全窗口接受 `UTType.image`（HEIC/JPEG/PNG/TIFF/WebP 等系统可解码格式）；非图片条目忽略。

## 8. 导出管线

1. `CompositionRenderer`：按输出像素宽度创建 `CGContext` 位图（尺寸 = 宽 × 宽/ratio），填背景色，按 `LayoutEngine` 几何以**原始 CGImage** 绘制（fill 用 sourceRect 裁剪；fit 居中贴图）。
2. `ImageExporter`：ImageIO 编码——PNG 无损；JPEG 质量 0.92。保存走 `NSSavePanel`。
3. 剪贴板：`NSPasteboard` 写图像数据，可直接去小红书粘贴。

## 9. 图像处理要点

- **EXIF 方向**：加载时通过 `CGImageSource` 读取 orientation 并预先旋转规范化为正向 CGImage，避免 iPhone 照片横躺。
- **大图性能**：加载时同时生成降采样缩略图（`CGImageSourceCreateThumbnailAtIndex`）；预览只用缩略图，导出用原图。两张超长截图拼接不卡顿。
- 图片解码失败：跳过该文件并在界面提示（不打断整批）。

## 10. 边界情况

- 单张图：可用（相当于给一张图定比例裁剪/留白），无边界手柄。
- weights 与 items 数量不一致：按均分兜底。
- 极端比例（如 20:1）：实时预览兜底，用户自行调整。
- 删除图片后同步清理 weights/policies。
- 0 张图：空态提示。
- 窗口尺寸变化：预览等比缩放，布局不变。

## 11. 测试策略

- **LayoutEngine 单测（重点）**：
  - 均分：3 图垂直，各占 1/3；
  - 权重归一化与 gap/margin 正确性；
  - fill 三种对齐（start/center/end）的 sourceRect 断言（用已知尺寸构造图）；
  - fit 留白：fittedFrame 缩放包含于条带；
  - 水平拼接对称性；
  - 画布比例：H = W / ratio。
- **渲染器单测**：小尺寸构造图渲染，断言输出像素尺寸 + 安全采样点颜色（角落背景色、gap 区域背景色）。
- **UI 手测清单**：拖入多图、排序、删除、追加、拖边界、切方向/比例、改策略、导出、复制剪贴板、EXIF 照片方向正确。

## 12. 非目标（第一版明确不做）

- 拉伸变形填满（画质灾难）
- 工程文件保存 / 文档型多窗口（需要时加轻量草稿恢复即可）
- 圆角、边框、水印、文字标注
- 智能主体识别裁剪
- 分发签名 / 公证 / 上架
- 撤销/重做（第一版策略切换成本低，YAGNI）

## 13. 技术栈与运行

- macOS 14+（Sonoma，SwiftUI 功能足够且用户系统为新版）
- SwiftUI + AppKit 桥接（拖放用 NSViewRepresentable / `.dropDestination`）
- Swift 5.9+，Xcode 15+，Swift Package 可选（直接 Xcode 工程亦可）
- 无第三方依赖
