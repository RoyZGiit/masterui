import Foundation

// MARK: - GroupChatDebugLogger

/// Appends structured debug logs for each group chat session.
/// Logs are written to a per-session file only (no stdout).
final class GroupChatDebugLogger {
    static let shared = GroupChatDebugLogger()

    private let queue = DispatchQueue(label: "com.masterui.groupchat.debuglog")
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    func log(
        groupSession: GroupChatSession,
        participantSessionID: UUID?,
        category: String,
        decision: String,
        detail: String? = nil,
        output: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let ts = formatter.string(from: Date())
        let participant = participantSessionID?.uuidString ?? "-"
        let base = "[GroupChatDebug] ts=\(ts) chat=\(groupSession.id.uuidString) participant=\(participant) category=\(category) decision=\(decision)"

        var line = base
        if let detail, !detail.isEmpty {
            line += " detail=\(sanitizeSingleLine(detail))"
        }
        if !metadata.isEmpty {
            let renderedMeta = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(sanitizeSingleLine($0.value))" }
                .joined(separator: " ")
            line += " \(renderedMeta)"
        }

        queue.async {
            let historyStore = GroupChatHistoryStore.shared
            let path = historyStore.debugLogFilePath(for: groupSession)
            let url = URL(fileURLWithPath: path)
            let fm = FileManager.default

            let parent = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            var chunks: [String] = [line + "\n"]
            if let output, !output.isEmpty {
                chunks.append("[GroupChatDebugOutput] ts=\(ts) chat=\(groupSession.id.uuidString) participant=\(participant) category=\(category)\n")
                chunks.append(output)
                if !output.hasSuffix("\n") {
                    chunks.append("\n")
                }
                chunks.append("[GroupChatDebugOutputEnd] ts=\(ts) chat=\(groupSession.id.uuidString) participant=\(participant) category=\(category)\n")
            }

            let payload = chunks.joined()
            if let data = payload.data(using: .utf8) {
                if fm.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        do {
                            try handle.seekToEnd()
                            try handle.write(contentsOf: data)
                        } catch {
                            print("[GroupChatDebug] failed writing log: \(error)")
                        }
                    }
                } else {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    private func sanitizeSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
