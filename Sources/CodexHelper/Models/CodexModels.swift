import Foundation

/// Codex 全局运行状态
enum CodexRunStatus: String, Sendable {
    case idle
    case running
    case waiting

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .running: return "运行中"
        case .waiting: return "等待中"
        }
    }
}

/// 单个任务状态
enum CodexTaskState: String, Sendable {
    case running
    case waiting
    case idle
    case completed
    case failed

    var label: String {
        switch self {
        case .running: return "运行中"
        case .waiting: return "等待确认"
        case .idle: return "空闲"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

/// 额度窗口快照
struct QuotaWindow: Identifiable, Sendable {
    let id: String
    let label: String
    /// API 返回的已用百分比
    let usedPercent: Int
    let resetAt: Date?
    let resetAfterSeconds: Int?
    let accent: QuotaAccent

    /// 剩余额度百分比（界面展示用）
    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

enum QuotaAccent: Sendable {
    case primary
    case secondary
}

/// 监控到的 Codex 任务
struct CodexTask: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let state: CodexTaskState
    let workspace: String?
    let updatedAt: Date
}

/// 额度 API 响应
struct CodexUsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    struct RateLimitDetails: Decodable, Sendable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable, Sendable {
        let usedPercent: Int
        let resetAt: Int?
        let resetAfterSeconds: Int?
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case resetAfterSeconds = "reset_after_seconds"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

/// OAuth 凭证
struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let accountId: String?
    let lastRefresh: Date?

    var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 3600
    }
}

enum CodexAuthError: LocalizedError, Sendable {
    case notFound
    case invalidFormat
    case refreshFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到 ~/.codex/auth.json，请先登录 Codex"
        case .invalidFormat:
            return "auth.json 格式无效"
        case .refreshFailed:
            return "Token 刷新失败，请重新登录 Codex"
        case .unauthorized:
            return "登录态已失效，请重新登录 Codex"
        }
    }
}

enum CodexUsageError: LocalizedError, Sendable {
    case network(String)
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "网络错误：\(message)"
        case .invalidResponse:
            return "额度接口返回无效数据"
        case .server(let code):
            return "额度接口错误（\(code)）"
        }
    }
}
