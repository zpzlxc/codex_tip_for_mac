import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private weak var panelController: FloatingPanelController?
    private let settingsController: SettingsWindowController
    private var statusItem: NSStatusItem?
    private var togglePanelItem: NSMenuItem?

    init(
        appState: AppState,
        panelController: FloatingPanelController,
        settingsController: SettingsWindowController
    ) {
        self.appState = appState
        self.panelController = panelController
        self.settingsController = settingsController
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        if let icon = AppIconLoader.menuBarIcon() {
            button.image = icon
            button.imageScaling = .scaleProportionallyUpOrDown
        } else {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Codex Helper")
            button.image?.isTemplate = true
        }
        button.toolTip = "Codex Helper"

        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        togglePanelItem = append(to: menu, title: panelToggleTitle, action: #selector(togglePanel))
        append(to: menu, title: "刷新额度", action: #selector(refreshUsage))
        menu.addItem(.separator())
        append(to: menu, title: "设置…", action: #selector(openSettings))
        menu.addItem(.separator())
        append(to: menu, title: "退出 Codex Helper", action: #selector(quit))
        return menu
    }

    @discardableResult
    private func append(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = menuItem(title, action: action)
        menu.addItem(item)
        return item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private var panelToggleTitle: String {
        panelController?.isVisible == true ? "隐藏悬浮窗" : "显示悬浮窗"
    }

    func menuWillOpen(_ menu: NSMenu) {
        togglePanelItem?.title = panelToggleTitle
    }

    @objc private func togglePanel() {
        panelController?.toggle()
        togglePanelItem?.title = panelToggleTitle
    }

    @objc private func refreshUsage() {
        Task { await appState.refreshUsage(force: true) }
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
