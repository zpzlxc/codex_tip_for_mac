import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var quotaWindows: [QuotaWindow] = []
    @Published var resetCredits: CodexAccountSnapshot.ResetCredits?
    @Published var lastUsageRefresh: Date?
    @Published var usageError: String?

    /// 额度轮询间隔（秒），默认 10 分钟。
    var usagePollingInterval: TimeInterval = 600

    private var usageTimer: Timer?
    private var isRefreshingUsage = false

    func start() {
        SettingsStorage.load(into: self)
        Task { await refreshUsage() }
        restartUsageTimer()
    }

    func applyPollingSettings() {
        restartUsageTimer()
    }

    private func restartUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: usagePollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshUsage()
            }
        }
        if let usageTimer {
            RunLoop.main.add(usageTimer, forMode: .common)
        }
    }

    func refreshUsage() async {
        guard !isRefreshingUsage else { return }

        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            let snapshot = try await CodexAppServerService.fetchSnapshot()
            quotaWindows = buildQuotaWindows(from: snapshot.rateLimits)
            resetCredits = snapshot.resetCredits
            lastUsageRefresh = Date()
            usageError = nil
        } catch {
            usageError = error.localizedDescription
            NSLog("Codex 额度刷新失败：%@", error.localizedDescription)
        }
    }

    private func buildQuotaWindows(from limits: CodexAccountSnapshot.RateLimits) -> [QuotaWindow] {
        [
            makeQuotaWindow(id: "primary", snapshot: limits.primary),
            makeQuotaWindow(id: "secondary", snapshot: limits.secondary)
        ].compactMap { $0 }
    }

    private func makeQuotaWindow(id: String, snapshot: CodexAccountSnapshot.Window?) -> QuotaWindow? {
        guard let snapshot else { return nil }
        return QuotaWindow(
            id: id,
            usedPercent: snapshot.usedPercent,
            resetAt: snapshot.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
