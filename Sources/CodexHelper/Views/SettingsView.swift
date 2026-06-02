import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var usageMinutes: Double = 10
    @State private var taskSeconds: Double = 8
    @State private var saveHint: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("轮询间隔") {
                    Stepper(
                        "额度刷新：\(Int(usageMinutes)) 分钟",
                        value: $usageMinutes,
                        in: 5...60,
                        step: 5
                    )
                    Stepper(
                        "任务扫描：\(Int(taskSeconds)) 秒",
                        value: $taskSeconds,
                        in: 3...60,
                        step: 1
                    )
                }

                Section("说明") {
                    Text("修改后点击「保存」才会生效。")
                    Text("登录态来自 ~/.codex/auth.json，无需额外配置。")
                    Text("额度默认每 10 分钟请求一次。手动刷新最短间隔 2 分钟。")
                    Text("任务状态仅读取本地文件，不会向 OpenAI 发请求。")
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                if let saveHint {
                    Text(saveHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("恢复默认") {
                    usageMinutes = 10
                    taskSeconds = 8
                    saveHint = nil
                }

                Button("保存") {
                    handleSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 380)
        .onAppear(perform: syncFromAppState)
    }

    private func syncFromAppState() {
        usageMinutes = appState.usagePollingInterval / 60
        taskSeconds = appState.taskPollingInterval
        saveHint = nil
    }

    private func handleSave() {
        appState.usagePollingInterval = usageMinutes * 60
        appState.taskPollingInterval = taskSeconds
        appState.applyPollingSettings()
        SettingsStorage.save(usageMinutes: usageMinutes, taskSeconds: taskSeconds)
        saveHint = "已保存并生效"
    }
}
