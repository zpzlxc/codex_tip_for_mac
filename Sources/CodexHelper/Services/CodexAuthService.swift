import Foundation
import Security

/// 读取并维护 Codex 本地 OAuth 登录态
enum CodexAuthService {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func resolveAuthFileURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/auth.json"),
            home.appendingPathComponent(".config/codex/auth.json")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return candidates[0]
    }

    static func loadCredentials() throws -> CodexOAuthCredentials {
        let fileURL = resolveAuthFileURL()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try parseAuthFile(at: fileURL)
        }

        if let keychain = loadFromKeychain() {
            return keychain
        }

        throw CodexAuthError.notFound
    }

    static func ensureFreshCredentials() async throws -> CodexOAuthCredentials {
        let credentials = try loadCredentials()
        // 仅在 token 接近过期时主动刷新，避免每次查额度都触发 OAuth 请求
        guard credentials.needsRefresh, !credentials.refreshToken.isEmpty else {
            return credentials
        }
        let refreshed = try await refresh(credentials)
        try save(refreshed)
        return refreshed
    }

    static func fetchUsage(retryOnUnauthorized: Bool = true) async throws -> CodexUsageResponse {
        let credentials = try await ensureFreshCredentials()
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")

        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CodexUsageError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            case 401, 403:
                guard retryOnUnauthorized else {
                    throw CodexAuthError.unauthorized
                }
                let refreshed = try await refresh(try loadCredentials())
                try save(refreshed)
                return try await fetchUsage(retryOnUnauthorized: false)
            default:
                throw CodexUsageError.server(http.statusCode)
            }
        } catch let error as CodexUsageError {
            throw error
        } catch let error as CodexAuthError {
            throw error
        } catch {
            throw CodexUsageError.network(error.localizedDescription)
        }
    }

    private static func parseAuthFile(at url: URL) throws -> CodexOAuthCredentials {
        let data = try Data(contentsOf: url)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            let refreshToken = tokens["refresh_token"] as? String
        else {
            throw CodexAuthError.invalidFormat
        }

        let accountId = tokens["account_id"] as? String
        let lastRefresh = (json["last_refresh"] as? String).flatMap(isoDate)

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            lastRefresh: lastRefresh
        )
    }

    private static func save(_ credentials: CodexOAuthCredentials) throws {
        let fileURL = resolveAuthFileURL()
        var payload: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }

        payload["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        payload["tokens"] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
            "account_id": credentials.accountId as Any
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    private static func refresh(_ credentials: CodexOAuthCredentials) async throws -> CodexOAuthCredentials {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "client_id=\(clientID)",
            "refresh_token=\(credentials.refreshToken)",
            "scope=openid profile email"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CodexAuthError.refreshFailed
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else {
            throw CodexAuthError.refreshFailed
        }

        let refreshToken = (json["refresh_token"] as? String) ?? credentials.refreshToken
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: credentials.accountId,
            lastRefresh: Date()
        )
    }

    private static func loadFromKeychain() -> CodexOAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Codex Auth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String
        else {
            return nil
        }

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: tokens["account_id"] as? String,
            lastRefresh: (json["last_refresh"] as? String).flatMap(isoDate)
        )
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
