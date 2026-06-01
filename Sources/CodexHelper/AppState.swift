import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var runStatus: CodexRunStatus = .idle
    @Published var quotaWindows: [QuotaWindow] = []
    @Published var tasks: [CodexTask] = []
    @Published var planType: String?
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
        refreshTasks()
        Task { await refreshUsage() }

        taskTimer = Timer.scheduledTimer(withTimeInterval: taskPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTasks()
            }
        }

        usageTimer = Timer.scheduledTimer(withTimeInterval: usagePollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshUsage()
            }
        }

        if let timer = taskTimer { RunLoop.main.add(timer, forMode: .common) }
        if let timer = usageTimer { RunLoop.main.add(timer, forMode: .common) }

        fileWatcher = CodexFileWatcher(paths: watchPaths()) { [weak self] in
            Task { @MainActor in
                self?.refreshTasks()
            }
        }
        fileWatcher?.start()
    }

    func refreshTasks() {
        let activeTasks = taskMonitor.scanActiveTasks()
        tasks = activeTasks
        lastTaskRefresh = Date()
        runStatus = deriveRunStatus(from: activeTasks)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deriveRunStatus(from tasks: [CodexTask]) -> CodexRunStatus {
        if tasks.contains(where: { $0.state == .waiting }) {
            return .waiting
        }
        if tasks.contains(where: { $0.state == .running }) {
            return .running
        }
        return .idle
    }

    private func buildQuotaWindows(from usage: CodexUsageResponse) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let primary = usage.rateLimit?.primaryWindow {
            windows.append(
                QuotaWindow(
                    id: "primary",
                    label: windowLabel(seconds: primary.limitWindowSeconds, fallback: "5小时剩余"),
                    usedPercent: primary.usedPercent,
                    resetAt: primary.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    resetAfterSeconds: primary.resetAfterSeconds,
                    accent: .primary
                )
            )
        }

        if let secondary = usage.rateLimit?.secondaryWindow {
            windows.append(
                QuotaWindow(
                    id: "secondary",
                    label: windowLabel(seconds: secondary.limitWindowSeconds, fallback: "周剩余"),
                    usedPercent: secondary.usedPercent,
                    resetAt: secondary.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    resetAfterSeconds: secondary.resetAfterSeconds,
                    accent: .secondary
                )
            )
        }

        return windows
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
        let home = CodexAuthService.resolveAuthFileURL().deletingLastPathComponent()
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
