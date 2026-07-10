import Foundation

enum CodexActivityState: Sendable {
    case idle
    case running
    case awaitingApproval

    var title: String {
        switch self {
        case .idle:
            return "空闲中"
        case .running:
            return "运行中"
        case .awaitingApproval:
            return "待批准"
        }
    }
}

/// 额度窗口快照
struct QuotaWindow: Identifiable, Sendable {
    let id: String
    /// API 返回的已用百分比
    let usedPercent: Int
    let resetAt: Date?

    /// 剩余额度百分比（界面展示用）
    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CodexAccountSnapshot: Sendable {
    let rateLimits: RateLimits
    let resetCredits: ResetCredits?

    struct RateLimits: Sendable {
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Sendable {
        let usedPercent: Int
        let resetsAt: Int?
    }

    struct ResetCredits: Sendable {
        let availableCount: Int
        let expiresAt: [Int]
    }
}

enum CodexAppServerError: LocalizedError, Sendable {
    case executableNotFound
    case unavailable(String)
    case rpc(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未找到 Codex，请先安装 Codex Desktop 或 CLI"
        case .unavailable(let message):
            return "Codex app-server 启动失败：\(message)"
        case .rpc(let message):
            return "Codex app-server 错误：\(message)"
        case .invalidResponse:
            return "Codex app-server 未返回有效额度"
        }
    }
}
