import Foundation

/// 持久化轮询间隔设置
@MainActor
enum SettingsStorage {
    private static let usageIntervalKey = "codex.helper.usagePollingInterval"

    static func load(into appState: AppState) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: usageIntervalKey) != nil {
            let minutes = defaults.double(forKey: usageIntervalKey)
            appState.usagePollingInterval = max(5, min(60, minutes)) * 60
        }
    }

    static func save(usageMinutes: Double) {
        UserDefaults.standard.set(usageMinutes, forKey: usageIntervalKey)
    }
}
