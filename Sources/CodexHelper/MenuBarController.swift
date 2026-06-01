import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let appState: AppState
    private weak var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    init(appState: AppState, panelController: FloatingPanelController) {
        self.appState = appState
        self.panelController = panelController
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Codex Helper")
        button.image?.isTemplate = true
        button.toolTip = "Codex Helper — 点击显示悬浮窗"

        menu = buildMenu()
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "显示悬浮窗",
            action: #selector(showPanel),
            keyEquivalent: "w"
        )
        menu.addItem(
            withTitle: "刷新额度",
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出 Codex Helper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showPanel()
            return
        }

        let isRightClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isRightClick, let menu, let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            return
        }

        showPanel()
    }

    @objc private func showPanel() {
        panelController?.show()
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func refreshUsage() {
        Task { await appState.refreshUsage(force: true) }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
