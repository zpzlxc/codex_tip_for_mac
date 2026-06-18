import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController!
    private var settingsController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIconLoader.loadBundleIcon()

        settingsController = SettingsWindowController(appState: appState)
        menuBarController = MenuBarController(
            appState: appState,
            settingsController: settingsController
        )
        menuBarController.setup()

        appState.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
