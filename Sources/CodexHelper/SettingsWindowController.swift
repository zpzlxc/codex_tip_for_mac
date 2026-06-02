import AppKit
import SwiftUI

/// 独立设置窗口（菜单栏应用无法依赖 SwiftUI Settings 场景）
@MainActor
final class SettingsWindowController {
    private let appState: AppState
    private var window: NSWindow?
    private var hostingView: NSHostingView<SettingsView>?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if window == nil {
            createWindow()
        }

        hostingView?.rootView = SettingsView(appState: appState)

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let hosting = NSHostingView(rootView: SettingsView(appState: appState))
        let contentSize = NSSize(width: 480, height: 380)
        hosting.frame = NSRect(origin: .zero, size: contentSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Helper 设置"
        window.contentView = hosting
        window.setContentSize(contentSize)
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        self.hostingView = hosting
    }
}
