import Foundation
import SQLite3

/// 通过本地 Codex 数据检测运行中的任务（无网络请求）
final class CodexTaskMonitor: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "codex.task.monitor", qos: .utility)

    private var codexHome: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func scanActiveTasks() -> [CodexTask] {
        var tasks: [CodexTask] = []
        var seen = Set<String>()

        tasks.append(contentsOf: parseChatProcesses(seen: &seen))
        tasks.append(contentsOf: parseRecentSessions(seen: &seen))
        tasks.append(contentsOf: parseAgentJobs(seen: &seen))

        return tasks.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - chat_processes.json

    private func parseChatProcesses(seen: inout Set<String>) -> [CodexTask] {
        let url = codexHome.appendingPathComponent("process_manager/chat_processes.json")
        guard
            let data = try? Data(contentsOf: url),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return array.compactMap { item in
            let threadId = (item["thread_id"] as? String)
                ?? (item["threadId"] as? String)
                ?? (item["id"] as? String)
            guard let threadId, !threadId.isEmpty, !seen.contains(threadId) else {
                return nil
            }

            seen.insert(threadId)
            let title = (item["title"] as? String)
                ?? (item["thread_name"] as? String)
                ?? threadTitle(from: threadId)
            let stateRaw = (item["status"] as? String) ?? "running"
            let state = mapProcessStatus(stateRaw)

            return CodexTask(
                id: threadId,
                title: title,
                state: state,
                workspace: item["cwd"] as? String ?? item["workspace"] as? String,
                updatedAt: Date()
            )
        }
    }

    // MARK: - session jsonl

    private func parseRecentSessions(seen: inout Set<String>) -> [CodexTask] {
        let sessionsRoot = codexHome.appendingPathComponent("sessions")
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-6 * 3600)
        var recentFiles: [(URL, Date)] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                let modified = values.contentModificationDate,
                modified >= cutoff
            else {
                continue
            }
            recentFiles.append((fileURL, modified))
        }

        recentFiles.sort { $0.1 > $1.1 }
        recentFiles = Array(recentFiles.prefix(12))

        return recentFiles.compactMap { pair in
            parseSessionFile(pair.0, modifiedAt: pair.1, seen: &seen)
        }
    }

    private func parseSessionFile(_ url: URL, modifiedAt: Date, seen: inout Set<String>) -> CodexTask? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let readSize = min(max(fileSize, 0), 96_000)
        guard readSize > 0 else { return nil }

        try? handle.seek(toOffset: UInt64(max(0, fileSize - readSize)))
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else {
            return nil
        }

        let text = String(decoding: chunk, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return nil }

        var threadId: String?
        var title: String?
        var workspace: String?
        var lastTaskStarted: Date?
        var lastTaskComplete: Date?
        var hasPendingToolCall = false
        var lastUserMessageAt: Date?
        var lastAgentMessageAt: Date?

        for line in lines {
            guard
                let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = obj["payload"] as? [String: Any]
            else {
                continue
            }

            let eventType = obj["type"] as? String
            let timestamp = (obj["timestamp"] as? String).flatMap(parseTimestamp) ?? modifiedAt

            if eventType == "session_meta" {
                threadId = payload["id"] as? String ?? threadId
                title = (payload["thread_name"] as? String) ?? title
                workspace = payload["cwd"] as? String ?? workspace
            }

            if eventType == "event_msg" {
                let msgType = payload["type"] as? String
                switch msgType {
                case "task_started":
                    lastTaskStarted = timestamp
                case "task_complete":
                    lastTaskComplete = timestamp
                case "user_message":
                    lastUserMessageAt = timestamp
                case "agent_message":
                    lastAgentMessageAt = timestamp
                default:
                    break
                }
            }

            if eventType == "response_item" {
                let itemType = payload["type"] as? String
                if itemType == "function_call" {
                    hasPendingToolCall = true
                } else if itemType == "function_call_output" {
                    hasPendingToolCall = false
                }
            }
        }

        if threadId == nil {
            threadId = extractThreadID(from: url.lastPathComponent)
        }

        guard let threadId, !seen.contains(threadId) else {
            return nil
        }

        let state = resolveSessionState(
            modifiedAt: modifiedAt,
            lastTaskStarted: lastTaskStarted,
            lastTaskComplete: lastTaskComplete,
            hasPendingToolCall: hasPendingToolCall,
            lastUserMessageAt: lastUserMessageAt,
            lastAgentMessageAt: lastAgentMessageAt
        )

        guard state == .running || state == .waiting else {
            return nil
        }

        seen.insert(threadId)
        return CodexTask(
            id: threadId,
            title: title ?? threadTitle(from: threadId),
            state: state,
            workspace: workspace,
            updatedAt: modifiedAt
        )
    }

    private func resolveSessionState(
        modifiedAt: Date,
        lastTaskStarted: Date?,
        lastTaskComplete: Date?,
        hasPendingToolCall: Bool,
        lastUserMessageAt: Date?,
        lastAgentMessageAt: Date?
    ) -> CodexTaskState {
        let recentlyModified = Date().timeIntervalSince(modifiedAt) < 120

        if let started = lastTaskStarted {
            if let completed = lastTaskComplete {
                if started > completed, recentlyModified {
                    return hasPendingToolCall ? .running : .running
                }
            } else if recentlyModified {
                return .running
            }
        }

        if hasPendingToolCall, recentlyModified {
            return .running
        }

        if let userAt = lastUserMessageAt {
            let agentAt = lastAgentMessageAt ?? .distantPast
            if userAt > agentAt, recentlyModified {
                return .running
            }
        }

        return .idle
    }

    // MARK: - agent jobs

    private func parseAgentJobs(seen: inout Set<String>) -> [CodexTask] {
        let dbURL = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: dbURL.path) else {
            return []
        }

        var tasks: [CodexTask] = []
        var db: OpaquePointer?

        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, name, status, instruction, updated_at
        FROM agent_jobs
        WHERE status IN ('running', 'pending', 'in_progress', 'waiting')
        ORDER BY updated_at DESC
        LIMIT 8
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            guard !seen.contains(id) else { continue }

            let name = String(cString: sqlite3_column_text(statement, 1))
            let status = String(cString: sqlite3_column_text(statement, 2))
            let instruction = String(cString: sqlite3_column_text(statement, 3))
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))

            seen.insert(id)
            tasks.append(
                CodexTask(
                    id: id,
                    title: name.isEmpty ? instruction : name,
                    state: mapProcessStatus(status),
                    workspace: nil,
                    updatedAt: updatedAt
                )
            )
        }

        return tasks
    }

    // MARK: - helpers

    private func mapProcessStatus(_ raw: String) -> CodexTaskState {
        switch raw.lowercased() {
        case "running", "in_progress", "thinking", "active":
            return .running
        case "waiting", "pending", "approval", "awaiting_approval":
            return .waiting
        case "failed", "error":
            return .failed
        case "completed", "done":
            return .completed
        default:
            return .running
        }
    }

    private func threadTitle(from threadId: String) -> String {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard
            let content = try? String(contentsOf: indexURL, encoding: .utf8)
        else {
            return "线程 \(threadId.prefix(8))"
        }

        for line in content.split(separator: "\n").reversed() {
            guard
                let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = obj["id"] as? String,
                id == threadId,
                let name = obj["thread_name"] as? String,
                !name.isEmpty
            else {
                continue
            }
            return name
        }

        return "线程 \(threadId.prefix(8))"
    }

    private func extractThreadID(from filename: String) -> String? {
        guard let range = filename.range(of: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, options: .regularExpression) else {
            return nil
        }
        return String(filename[range])
    }

    private func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
