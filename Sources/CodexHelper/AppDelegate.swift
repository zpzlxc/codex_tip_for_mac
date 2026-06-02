import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var panelController: FloatingPanelController!
    private var menuBarController: MenuBarController!
    private var settingsController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIconLoader.loadBundleIcon()

        panelController = FloatingPanelController(appState: appState)
        panelController.show()

        settingsController = SettingsWindowController(appState: appState)
        menuBarController = MenuBarController(
            appState: appState,
            panelController: panelController,
            settingsController: settingsController
        )
        menuBarController.setup()

        appState.start()
    }

    /// 再次点击 Dock / 启动 .app 时恢复悬浮窗
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
