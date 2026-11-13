import SwiftUI
import AppKit

enum AboutPanel {
    @MainActor
    static func show() {
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        pStyle.lineSpacing = 4

        let credits = NSMutableAttributedString(
            string: "vibe by hewN with GLM & Gemini\nweibo@heptagonal",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: pStyle
            ]
        )
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "PicPin",
            .applicationVersion: version,
            .version: "Liquid Glass",
            .credits: credits
        ])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run 启动的进程无 bundle，需手动成为正规前台应用
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            Self.ensureMinimumWindowSize()
        }
    }

    @MainActor
    private static func ensureMinimumWindowSize() {
        for window in NSApp.windows {
            window.contentMinSize = NSSize(width: 1120, height: 720)
            let frame = window.frame
            if frame.width < 1160 || frame.height < 740 {
                let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                let targetW = min(max(frame.width, 1220), visible?.width ?? 1220)
                let targetH = min(max(frame.height, 780), visible?.height ?? 780)
                window.setContentSize(NSSize(width: targetW, height: targetH))
                window.center()
            }
        }
    }

    /// 点击窗口左上角 × 关闭主窗口时直接退出应用，避免空进程残留后台无法重新唤起
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 点击 Dock / 菜单栏应用图标时，恢复被最小化或隐藏的窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

@main
struct PicPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1220, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 PicPin") {
                    AboutPanel.show()
                }
            }
        }
    }
}
