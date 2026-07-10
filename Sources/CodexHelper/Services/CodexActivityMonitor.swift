import Foundation

actor CodexActivityMonitor {
    private struct SessionProgress {
        var offset: UInt64 = 0
        var unfinishedTurns: [String: Date] = [:]
        var pendingApprovalCalls: [String: Date] = [:]
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
    private let staleTurnAge: TimeInterval = 10 * 60

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
            updateSession(at: url, fileSize: UInt64(values.fileSize ?? 0), now: Date())
        }

        sessions = sessions.filter { activeURLs.contains($0.key) }
    }

    private func updateSession(at url: URL, fileSize: UInt64, now: Date) {
        var progress = sessions[url] ?? SessionProgress()

        if fileSize < progress.offset {
            progress = SessionProgress()
        }
        guard fileSize > progress.offset else {
            pruneStaleState(from: &progress, now: now)
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
            consumeCompleteLines(from: &progress, now: now)
            pruneStaleState(from: &progress, now: now)
            sessions[url] = progress
        } catch {
            return
        }
    }

    private func consumeCompleteLines(from progress: inout SessionProgress, now: Date) {
        while let newline = progress.trailingData.firstIndex(of: 0x0A) {
            let line = progress.trailingData.prefix(upTo: newline)
            progress.trailingData.removeSubrange(...newline)
            consume(line: Data(line), into: &progress, now: now)
        }
    }

    private func consume(line: Data, into progress: inout SessionProgress, now: Date) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return
        }
        let eventDate = (object["timestamp"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? now

        if type == "event_msg", let eventType = payload["type"] as? String {
            guard let turnID = payload["turn_id"] as? String else { return }
            if eventType == "task_started" {
                progress.unfinishedTurns[turnID] = eventDate
            } else if eventType == "task_complete" {
                progress.unfinishedTurns.removeValue(forKey: turnID)
                if progress.unfinishedTurns.isEmpty {
                    progress.pendingApprovalCalls.removeAll()
                }
            } else if progress.unfinishedTurns[turnID] != nil {
                progress.unfinishedTurns[turnID] = eventDate
            }
            return
        }

        guard type == "response_item", let itemType = payload["type"] as? String else {
            return
        }

        if itemType == "function_call",
           let callID = payload["call_id"] as? String,
           requestsApproval(payload["arguments"]) {
            progress.pendingApprovalCalls[callID] = now
        } else if itemType == "function_call_output",
                  let callID = payload["call_id"] as? String {
            progress.pendingApprovalCalls.removeValue(forKey: callID)
        }
    }

    private func pruneStaleState(from progress: inout SessionProgress, now: Date) {
        progress.unfinishedTurns = progress.unfinishedTurns.filter {
            now.timeIntervalSince($0.value) < staleTurnAge
        }
        progress.pendingApprovalCalls = progress.pendingApprovalCalls.filter {
            now.timeIntervalSince($0.value) < staleTurnAge
        }
        if progress.unfinishedTurns.isEmpty {
            progress.pendingApprovalCalls.removeAll()
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
