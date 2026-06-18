import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var usageMinutes: Double = 10
    @State private var saveHint: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("轮询间隔") {
                    Stepper(
                        "额度刷新：\(Int(usageMinutes)) 分钟",
                        value: $usageMinutes,
                        in: 5...60,
                        step: 1
                    )
                }

                Section("说明") {
                    Text("修改后点击「保存」才会生效。")
                    Text("账号与额度通过本机 Codex app-server 读取。")
                    Text("额度默认每 10 分钟请求一次，也可从菜单手动刷新。")
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
        .frame(width: 440, height: 300)
        .onAppear(perform: syncFromAppState)
    }

    private func syncFromAppState() {
        usageMinutes = appState.usagePollingInterval / 60
        saveHint = nil
    }

    private func handleSave() {
        appState.usagePollingInterval = usageMinutes * 60
        appState.applyPollingSettings()
        SettingsStorage.save(usageMinutes: usageMinutes)
        saveHint = "已保存并生效"
    }
}
