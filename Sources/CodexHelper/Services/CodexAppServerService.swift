import Foundation

/// 通过 Codex 官方 app-server 协议读取账号与额度。
enum CodexAppServerService {
    private static let initializeID = 1
    private static let rateLimitsID = 2

    static func fetchSnapshot() async throws -> CodexAccountSnapshot {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await fetchSnapshotOnce()
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw lastError ?? CodexAppServerError.invalidResponse
    }

    private static func fetchSnapshotOnce() async throws -> CodexAccountSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "codex.helper.app-server")
            queue.async {
                do {
                    continuation.resume(returning: try runAppServer())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runAppServer() throws -> CodexAccountSnapshot {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = try CodexPaths.executableURL()
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        // `availableData` 会阻塞到有数据为止，不能直接放在带 deadline 的循环中。
        // 通过可读事件等待，才能在 app-server 或网络卡住时真正超时并释放刷新锁。
        let outputReady = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { _ in
            outputReady.signal()
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
        }

        try send(
            [
                "method": "initialize",
                "id": initializeID,
                "params": [
                    "clientInfo": [
                        "name": "codex_helper",
                        "title": "Codex Helper",
                        "version": "1.0.0"
                    ]
                ]
            ],
            to: input.fileHandleForWriting
        )

        var buffer = Data()
        var limits: CodexAccountSnapshot.RateLimits?
        var didInitialize = false
        let deadline = Date().addingTimeInterval(20)

        while Date() < deadline, process.isRunning {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0,
                  outputReady.wait(timeout: .now() + remaining) == .success
            else {
                break
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard
                    !line.isEmpty,
                    let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                else {
                    continue
                }

                if let error = message["error"] as? [String: Any] {
                    throw CodexAppServerError.rpc(error["message"] as? String ?? "未知错误")
                }

                guard let id = (message["id"] as? NSNumber)?.intValue else {
                    continue
                }

                if id == initializeID, !didInitialize {
                    didInitialize = true
                    try send(["method": "initialized", "params": [:]], to: input.fileHandleForWriting)
                    try send(
                        ["method": "account/rateLimits/read", "id": rateLimitsID],
                        to: input.fileHandleForWriting
                    )
                } else if id == rateLimitsID {
                    limits = parseRateLimits(from: message)
                }

                if let limits {
                    return CodexAccountSnapshot(
                        rateLimits: limits,
                        resetCredits: parseResetCredits(from: message)
                    )
                }
            }
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        let errorText = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let errorText, !errorText.isEmpty {
            throw CodexAppServerError.unavailable(errorText)
        }
        throw CodexAppServerError.invalidResponse
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func parseRateLimits(from message: [String: Any]) -> CodexAccountSnapshot.RateLimits? {
        guard let result = message["result"] as? [String: Any] else { return nil }

        // 合并版客户端仍会返回兼容的 Codex 单桶视图；优先使用它以保持
        // 原有 5 小时/1 周显示逻辑。仅在该字段缺失时兼容新版多桶结构。
        let limitBuckets = result["rateLimitsByLimitId"] as? [String: Any]
        let limits = (result["rateLimits"] as? [String: Any])
            ?? (limitBuckets?["codex"] as? [String: Any])
            ?? (limitBuckets?.values.compactMap { $0 as? [String: Any] }.first)
        guard let limits else { return nil }

        return .init(
            primary: parseWindow(limits["primary"]),
            secondary: parseWindow(limits["secondary"])
        )
    }

    private static func parseWindow(_ value: Any?) -> CodexAccountSnapshot.Window? {
        guard let window = value as? [String: Any] else { return nil }
        return .init(
            usedPercent: (window["usedPercent"] as? NSNumber)?.intValue ?? 0,
            resetsAt: (window["resetsAt"] as? NSNumber)?.intValue
        )
    }

    private static func parseResetCredits(from message: [String: Any]) -> CodexAccountSnapshot.ResetCredits? {
        guard
            let result = message["result"] as? [String: Any],
            let credits = result["rateLimitResetCredits"] as? [String: Any],
            let availableCount = (credits["availableCount"] as? NSNumber)?.intValue
        else {
            return nil
        }

        // 该数组就是服务端随可用刷新次数一起返回的刷新券明细；不同客户端
        // 版本的 status 字段并不完全一致，因此只按每条 expiresAt 展示。
        let creditEntries = credits["credits"] as? [Any] ?? []
        let expiresAt = creditEntries
            .compactMap { $0 as? [String: Any] }
            .compactMap { ($0["expiresAt"] as? NSNumber)?.intValue }
            .sorted()
        return .init(availableCount: availableCount, expiresAt: expiresAt)
    }
}

enum CodexPaths {
    static func homeURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func executableURL() throws -> URL {
        let environmentPath = ProcessInfo.processInfo.environment["CODEX_EXECUTABLE"]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/codex" }
        let candidates = [
            environmentPath,
            // 新版 ChatGPT/Codex 合并客户端将内置 CLI 放在 ChatGPT.app 内。
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].compactMap { $0 } + pathCandidates

        if let path = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return URL(fileURLWithPath: path)
        }
        throw CodexAppServerError.executableNotFound
    }
}
