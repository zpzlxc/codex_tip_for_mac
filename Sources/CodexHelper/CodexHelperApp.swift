import SwiftUI

@main
struct CodexHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}
