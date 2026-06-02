import SwiftUI

@main
struct CodexHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 设置窗口由 SettingsWindowController 手动管理
        Settings {
            EmptyView()
        }
    }
}
