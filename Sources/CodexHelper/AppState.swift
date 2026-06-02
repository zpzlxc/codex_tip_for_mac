import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var quotaWindows: [QuotaWindow] = []
    @Published var tasks: [CodexTask] = []
    @Published var planType: String?
    @Published var accountEmail: String?
    @Published var lastUsageRefresh: Date?
    @Published var lastTaskRefresh: Date?
    @Published var errorMessage: String?
    @Published var isRefreshingUsage = false

    /// 额度轮询间隔（秒），默认 10 分钟，降低封号风险
    var usagePollingInterval: TimeInterval = 600
    /// 本地任务扫描间隔（秒），默认 8 秒
    var taskPollingInterval: TimeInterval = 8
    /// 两次额度请求之间的最短间隔（秒），防止误触频繁刷新
    private let minimumUsageFetchInterval: TimeInterval = 120

    private let taskMonitor = CodexTaskMonitor()
    private var usageTimer: Timer?
    private var taskTimer: Timer?
    private var fileWatcher: CodexFileWatcher?
    private var lastUsageFetchAttempt: Date?

    func start() {
        SettingsStorage.load(into: self)
        accountEmail = CodexAuthService.loadAccountEmail()
        refreshTasks()
        Task { await refreshUsage() }
        restartTaskTimer()
        restartUsageTimer()

        fileWatcher = CodexFileWatcher(paths: watchPaths()) { [weak self] in
            Task { @MainActor in
                self?.refreshTasks()
            }
        }
        fileWatcher?.start()
    }

    /// 设置页修改轮询间隔后重建定时器
    func applyPollingSettings() {
        restartTaskTimer()
        restartUsageTimer()
    }

    private func restartTaskTimer() {
        restartTimer(&taskTimer, interval: taskPollingInterval) { [weak self] in
            self?.refreshTasks()
        }
    }

    private func restartUsageTimer() {
        restartTimer(&usageTimer, interval: usagePollingInterval) { [weak self] in
            Task { await self?.refreshUsage() }
        }
    }

    private func restartTimer(_ timer: inout Timer?, interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                action()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refreshTasks() {
        let activeTasks = taskMonitor.scanActiveTasks()
        tasks = activeTasks
        lastTaskRefresh = Date()
    }

    func refreshUsage(force: Bool = false) async {
        guard !isRefreshingUsage else { return }

        if !force,
           let lastAttempt = lastUsageFetchAttempt,
           Date().timeIntervalSince(lastAttempt) < minimumUsageFetchInterval {
            return
        }

        isRefreshingUsage = true
        lastUsageFetchAttempt = Date()
        defer { isRefreshingUsage = false }

        do {
            let usage = try await CodexAuthService.fetchUsage()
            planType = usage.planType
            quotaWindows = buildQuotaWindows(from: usage)
            lastUsageRefresh = Date()
            errorMessage = nil
            if accountEmail == nil {
                accountEmail = CodexAuthService.loadAccountEmail()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildQuotaWindows(from usage: CodexUsageResponse) -> [QuotaWindow] {
        [
            makeQuotaWindow(
                id: "primary",
                snapshot: usage.rateLimit?.primaryWindow,
                fallback: "5小时剩余",
                accent: .primary
            ),
            makeQuotaWindow(
                id: "secondary",
                snapshot: usage.rateLimit?.secondaryWindow,
                fallback: "周剩余",
                accent: .secondary
            )
        ].compactMap { $0 }
    }

    private func makeQuotaWindow(
        id: String,
        snapshot: CodexUsageResponse.WindowSnapshot?,
        fallback: String,
        accent: QuotaAccent
    ) -> QuotaWindow? {
        guard let snapshot else { return nil }
        return QuotaWindow(
            id: id,
            label: windowLabel(seconds: snapshot.limitWindowSeconds, fallback: fallback),
            usedPercent: snapshot.usedPercent,
            resetAt: snapshot.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            resetAfterSeconds: snapshot.resetAfterSeconds,
            accent: accent
        )
    }

    private func windowLabel(seconds: Int?, fallback: String) -> String {
        guard let seconds else { return fallback }
        switch seconds {
        case 17_000...19_000: return "5小时剩余"
        case 600_000...700_000: return "周剩余"
        default: return fallback
        }
    }

    private func watchPaths() -> [URL] {
        let home = CodexAuthService.resolveCodexHomeURL()
        return [
            home.appendingPathComponent("process_manager/chat_processes.json"),
            home.appendingPathComponent("sessions"),
            home.appendingPathComponent("state_5.sqlite-wal")
        ]
    }
}

/// 监听 Codex 本地文件变化，触发任务刷新
final class CodexFileWatcher: @unchecked Sendable {
    private let paths: [URL]
    private let callback: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var descriptors: [Int32] = []
    private let queue = DispatchQueue(label: "codex.file.watcher", qos: .utility)

    init(paths: [URL], callback: @escaping () -> Void) {
        self.paths = paths
        self.callback = callback
    }

    func start() {
        for path in paths {
            let fd = open(path.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            descriptors.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.callback()
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
        }
    }

    deinit {
        sources.forEach { $0.cancel() }
    }
}
