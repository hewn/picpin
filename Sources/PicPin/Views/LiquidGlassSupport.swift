import SwiftUI
import AppKit

/// 窗口级透光毛玻璃底衬（让窗口透出桌面壁纸色泽，衬托上层液态玻璃控件）
struct WindowBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 液态玻璃胶囊按钮样式（解决 macOS 下 .buttonStyle(.plain) 仅文字像素可点、周围胶囊空白处点击无反应的问题）
struct LiquidGlassChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .liquidGlassChip(isSelected: isSelected)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .contentShape(Capsule())
    }
}

extension View {
    /// 液态玻璃面板修饰符（macOS 26+ 原生 Liquid Glass，向下兼容高光半透明材质）
    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }

    /// 液态玻璃内部子卡片（轻透层次）
    @ViewBuilder
    func liquidGlassSection(cornerRadius: CGFloat = 12) -> some View {
        self.padding(10)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    /// 液态玻璃胶囊芯片（用于比例预设按钮等；不使用 .interactive() 以免拦截 Button 点击事件，并补全 Capsule 点击热区）
    @ViewBuilder
    func liquidGlassChip(isSelected: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self.contentShape(Capsule())
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor) : .clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.14),
                            lineWidth: isSelected ? 1.5 : 0.8
                        )
                )
                .contentShape(Capsule())
        } else {
            self.background(
                isSelected ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor).opacity(0.6),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.15), lineWidth: 1.2)
            )
            .contentShape(Capsule())
        }
    }

    /// 液态玻璃按钮样式
    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
