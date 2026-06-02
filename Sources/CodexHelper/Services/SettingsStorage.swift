import Foundation

/// 持久化轮询间隔设置
@MainActor
enum SettingsStorage {
    private static let usageIntervalKey = "codex.helper.usagePollingInterval"
    private static let taskIntervalKey = "codex.helper.taskPollingInterval"

    static func load(into appState: AppState) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: usageIntervalKey) != nil {
            let minutes = defaults.double(forKey: usageIntervalKey)
            appState.usagePollingInterval = max(5, min(60, minutes)) * 60
        }
        if defaults.object(forKey: taskIntervalKey) != nil {
            let seconds = defaults.double(forKey: taskIntervalKey)
            appState.taskPollingInterval = max(3, min(60, seconds))
        }
    }

    static func save(usageMinutes: Double, taskSeconds: Double) {
        let defaults = UserDefaults.standard
        defaults.set(usageMinutes, forKey: usageIntervalKey)
        defaults.set(taskSeconds, forKey: taskIntervalKey)
    }
}
