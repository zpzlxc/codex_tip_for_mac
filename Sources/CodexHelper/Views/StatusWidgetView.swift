import SwiftUI

struct StatusWidgetView: View {
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    private let trafficLightColumnWidth: CGFloat = 54
    private let infoBlockHeight: CGFloat = TrafficLightIndicator.fixedHeight

    private var hasActiveTasks: Bool {
        !appState.tasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            mainSection

            if hasActiveTasks {
                tasksFullWidthSection
            }

            footerSection
        }
        .padding(14)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WidgetTheme.background)
                .shadow(color: WidgetTheme.shadow, radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WidgetTheme.border, lineWidth: 1.2)
        )
    }

    // MARK: - 顶栏

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Codex 运行状态 & 额度监控")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.title)

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(WidgetTheme.closeButtonHover)
                    )
            }
            .buttonStyle(.plain)
            .help("退出应用")
        }
    }

    // MARK: - 主区域：左红绿灯 + 右状态与额度

    private var mainSection: some View {
        HStack(alignment: .top, spacing: 12) {
            TrafficLightIndicator(active: appState.runStatus)
                .frame(width: trafficLightColumnWidth, height: infoBlockHeight)

            VStack(alignment: .leading, spacing: 10) {
                statusInfoBlock
                quotaBlock
            }
            .frame(maxWidth: .infinity, minHeight: infoBlockHeight, alignment: .topLeading)
        }
    }

    private var statusInfoBlock: some View {
        HStack(spacing: 8) {
            Text("当前：\(appState.runStatus.label)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.primaryText)

            if let plan = appState.planType {
                Text(plan.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.accentBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(WidgetTheme.accentBlue.opacity(0.10))
                    )
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var quotaBlock: some View {
        if !appState.quotaWindows.isEmpty {
            VStack(spacing: 10) {
                ForEach(appState.quotaWindows) { window in
                    QuotaBarView(window: window)
                }
            }
        } else if appState.isRefreshingUsage {
            HStack(alignment: .center, spacing: 6) {
                Text("正在读取额度…")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.secondaryText)
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 任务列表（底部全宽）

    private var tasksFullWidthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活跃任务")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetTheme.secondaryText)

            ForEach(appState.tasks.prefix(5)) { task in
                TaskRowView(task: task)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 底栏

    private var footerSection: some View {
        HStack {
            if let error = appState.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(2)
            } else {
                Text(refreshHint)
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.tertiaryText)
            }

            Spacer()

            Button {
                Task { await appState.refreshUsage(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WidgetTheme.secondaryText)
            .help("手动刷新额度")
        }
    }

    private var refreshHint: String {
        let usage = appState.lastUsageRefresh.map(formatTime) ?? "未刷新"
        let tasks = appState.lastTaskRefresh.map(formatTime) ?? "未刷新"
        return "额度 \(usage) · 任务 \(tasks)"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 额度条

struct QuotaBarView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTheme.primaryText)
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.title)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WidgetTheme.trackBackground)
                    Capsule()
                        .fill(barGradient)
                        .frame(width: max(6, proxy.size.width * CGFloat(window.remainingPercent) / 100))
                }
            }
            .frame(height: 8)

            Text(resetHint)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.tertiaryText)
        }
    }

    private var resetHint: String {
        let usedSuffix = "已用 \(window.usedPercent)%"
        let resetDate = resolvedResetDate()

        if let resetDate {
            let preciseTime = formatPreciseReset(resetDate)
            if let seconds = window.resetAfterSeconds, seconds > 0 {
                return "\(formatDuration(seconds))后重置 · \(preciseTime) · \(usedSuffix)"
            }
            return "重置于 \(preciseTime) · \(usedSuffix)"
        }

        return usedSuffix
    }

    private func resolvedResetDate() -> Date? {
        if let resetAt = window.resetAt {
            return resetAt
        }
        if let seconds = window.resetAfterSeconds, seconds > 0 {
            return Date().addingTimeInterval(TimeInterval(seconds))
        }
        return nil
    }

    private func formatPreciseReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd a h:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 86_400 {
            return "\(seconds / 86_400)天"
        }
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时"
        }
        if seconds >= 60 {
            return "\(seconds / 60)分钟"
        }
        return "\(seconds)秒"
    }

    private var barGradient: LinearGradient {
        switch window.accent {
        case .primary:
            return LinearGradient(
                colors: [WidgetTheme.accentBlue, WidgetTheme.accentBlue.opacity(0.75)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .secondary:
            return LinearGradient(
                colors: [WidgetTheme.accentPurple, WidgetTheme.accentPurple.opacity(0.75)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

// MARK: - 任务行

struct TaskRowView: View {
    let task: CodexTask

    var body: some View {
        HStack(spacing: 8) {
            LEDStatusDotView(state: task.state)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(task.state.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(stateLabelColor)

                    if let workspace = task.workspace {
                        Text(shortPath(workspace))
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WidgetTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WidgetTheme.border.opacity(0.6), lineWidth: 0.8)
                )
        )
    }

    private var stateLabelColor: Color {
        switch task.state {
        case .running: return Color(red: 0.85, green: 0.55, blue: 0.05)
        case .waiting, .failed: return Color(red: 0.90, green: 0.22, blue: 0.22)
        case .completed, .idle: return Color(red: 0.12, green: 0.68, blue: 0.38)
        }
    }

    private func shortPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count > 2 else { return path }
        return components.suffix(2).joined(separator: "/")
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("轮询间隔") {
                Stepper(
                    "额度刷新：\(Int(appState.usagePollingInterval / 60)) 分钟",
                    value: Binding(
                        get: { appState.usagePollingInterval / 60 },
                        set: { appState.usagePollingInterval = $0 * 60 }
                    ),
                    in: 5...60,
                    step: 5
                )
                Stepper(
                    "任务扫描：\(Int(appState.taskPollingInterval)) 秒",
                    value: $appState.taskPollingInterval,
                    in: 3...60,
                    step: 1
                )
            }

            Section("说明") {
                Text("登录态来自 ~/.codex/auth.json，无需额外配置。")
                Text("额度默认每 10 分钟请求一次，界面展示剩余百分比。手动刷新最短间隔 2 分钟。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
        .padding()
    }
}
