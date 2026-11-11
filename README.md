# PicPin

把多张图片拖进来，拼成一张图，并可指定目标比例。切比例时不粗暴裁剪——每张子图可以单独选择「等比放大撑满 + 保留顶/中/底」或「完整显示留白」。

## 构建

需要 macOS 14+ 与 Xcode Command Line Tools。

```bash
swift build            # 开发构建
swift test             # 运行单元测试
swift run              # 直接运行
./Scripts/make-app.sh  # 打包 build/PicPin.app（未签名，首次右键打开）
```

## 使用

1. 从 Finder 把图片拖进窗口（可一次多张，继续拖入即追加）
2. 左栏拖动排序、点 × 删除
3. 右栏选择拼接方向与目标比例（预设 + 自定义 w:h）
4. 点选画布中某张图，选择它的策略：模式（撑满/完整显示）× 对齐（保留顶/中/底或左/中/右）
5. 拖动画布中的边界线微调每张图的占比（单条最小 5%）
6. 底部导出 PNG/JPEG（宽度可选）或直接复制到剪贴板

## 设计文档

见 `docs/superpowers/specs/2026-11-11-picpin-design.md`。
