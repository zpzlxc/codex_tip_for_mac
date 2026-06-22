import Foundation

actor CodexActivityMonitor {
    private struct SessionProgress {
        var offset: UInt64 = 0
        var unfinishedTurns = Set<String>()
        var pendingApprovalCalls = Set<String>()
        var trailingData = Data()

        var isRunning: Bool {
            !unfinishedTurns.isEmpty
        }

        var isAwaitingApproval: Bool {
            isRunning && !pendingApprovalCalls.isEmpty
        }
    }

    private var sessions: [URL: SessionProgress] = [:]
    private let recentSessionAge: TimeInterval = 2 * 24 * 60 * 60

    func currentState() -> CodexActivityState {
        updateSessions()

        if sessions.values.contains(where: \.isAwaitingApproval) {
            return .awaitingApproval
        }
        if sessions.values.contains(where: \.isRunning) {
            return .running
        }
        return .idle
    }

    private func updateSessions() {
        let fileManager = FileManager.default
        let sessionsURL = CodexPaths.homeURL().appendingPathComponent("sessions")
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            sessions.removeAll()
            return
        }

        let cutoff = Date().addingTimeInterval(-recentSessionAge)
        var activeURLs = Set<URL>()

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard
                let values = try? url.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true,
                let modificationDate = values.contentModificationDate,
                modificationDate >= cutoff
            else {
                continue
            }

            activeURLs.insert(url)
            updateSession(at: url, fileSize: UInt64(values.fileSize ?? 0))
        }

        sessions = sessions.filter { activeURLs.contains($0.key) }
    }

    private func updateSession(at url: URL, fileSize: UInt64) {
        var progress = sessions[url] ?? SessionProgress()

        if fileSize < progress.offset {
            progress = SessionProgress()
        }
        guard fileSize > progress.offset else {
            sessions[url] = progress
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: progress.offset)
            guard let newData = try handle.readToEnd(), !newData.isEmpty else {
                sessions[url] = progress
                return
            }

            progress.offset += UInt64(newData.count)
            progress.trailingData.append(newData)
            consumeCompleteLines(from: &progress)
            sessions[url] = progress
        } catch {
            return
        }
    }

    private func consumeCompleteLines(from progress: inout SessionProgress) {
        while let newline = progress.trailingData.firstIndex(of: 0x0A) {
            let line = progress.trailingData.prefix(upTo: newline)
            progress.trailingData.removeSubrange(...newline)
            consume(line: Data(line), into: &progress)
        }
    }

    private func consume(line: Data, into progress: inout SessionProgress) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return
        }

        if type == "event_msg", let eventType = payload["type"] as? String {
            guard let turnID = payload["turn_id"] as? String else { return }
            if eventType == "task_started" {
                progress.unfinishedTurns.insert(turnID)
            } else if eventType == "task_complete" {
                progress.unfinishedTurns.remove(turnID)
                if progress.unfinishedTurns.isEmpty {
                    progress.pendingApprovalCalls.removeAll()
                }
            }
            return
        }

        guard type == "response_item", let itemType = payload["type"] as? String else {
            return
        }

        if itemType == "function_call",
           let callID = payload["call_id"] as? String,
           requestsApproval(payload["arguments"]) {
            progress.pendingApprovalCalls.insert(callID)
        } else if itemType == "function_call_output",
                  let callID = payload["call_id"] as? String {
            progress.pendingApprovalCalls.remove(callID)
        }
    }

    private func requestsApproval(_ argumentsValue: Any?) -> Bool {
        guard
            let arguments = argumentsValue as? String,
            let data = arguments.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object["sandbox_permissions"] as? String == "require_escalated"
    }
}
