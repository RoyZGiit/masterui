import Foundation
import Combine

enum GroupChatTab {
    case conversation
    case history
}

// MARK: - GroupChatSession

/// Represents a single group chat where multiple CLI sessions participate.
class GroupChatSession: ObservableObject, Identifiable {
    let id: UUID
    let createdAt: Date

    @Published var title: String
    @Published var participantSessionIDs: [UUID]
    @Published var messages: [GroupMessage]
    @Published var lastActivityDate: Date
    @Published var hasUnreadActivity: Bool = false
    @Published var activeTab: GroupChatTab = .conversation

    /// Message sequence number, incremented on each append.
    @Published var sequence: Int = 0

    /// Event fired after each message append so subscribers can react immediately.
    struct MessageEvent {
        let message: GroupMessage
        let sequence: Int
    }

    let messagePublisher = PassthroughSubject<MessageEvent, Never>()

    init(
        id: UUID = UUID(),
        title: String,
        participantSessionIDs: [UUID],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.participantSessionIDs = participantSessionIDs
        self.messages = []
        self.createdAt = createdAt
        self.lastActivityDate = createdAt
    }

    func addParticipant(_ sessionID: UUID) {
        guard !participantSessionIDs.contains(sessionID) else { return }
        participantSessionIDs.append(sessionID)
    }

    func removeParticipant(_ sessionID: UUID) {
        participantSessionIDs.removeAll { $0 == sessionID }
    }

    func appendMessage(_ message: GroupMessage) {
        messages.append(message)
        sequence += 1
        lastActivityDate = Date()
        hasUnreadActivity = true
        messagePublisher.send(MessageEvent(message: message, sequence: sequence))
    }

    /// Returns all messages after the given sequence number.
    func messages(after afterSequence: Int) -> [GroupMessage] {
        let startIndex = afterSequence
        guard startIndex < messages.count else { return [] }
        return Array(messages[startIndex...])
    }

    /// Returns participant display names and disambiguates duplicate names with a stable alias.
    /// Example: "Codex@codex-1a2b3c"
    func participantDisplayNames(sessionManager: CLISessionManager) -> [UUID: String] {
        var baseNames: [UUID: String] = [:]
        for sessionID in participantSessionIDs {
            if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                baseNames[sessionID] = session.target.name
                continue
            }
            if let historical = messages.last(where: {
                if case .ai(_, let sid, _) = $0.source {
                    return sid == sessionID
                }
                return false
            }), case .ai(let name, _, _) = historical.source {
                baseNames[sessionID] = name
            }
        }

        let counts = Dictionary(grouping: baseNames.values, by: { $0 }).mapValues(\.count)
        var labels: [UUID: String] = [:]

        for sessionID in participantSessionIDs {
            let base = baseNames[sessionID] ?? "AI"
            if (counts[base] ?? 0) <= 1 {
                labels[sessionID] = base
                continue
            }
            let sourceTag: String
            if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                sourceTag = Self.sourceTag(for: session.target)
            } else {
                sourceTag = "cli"
            }
            labels[sessionID] = "\(base)@\(sourceTag)-\(Self.shortID(sessionID))"
        }

        return labels
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }

    private static func sourceTag(for target: AITarget) -> String {
        let raw = URL(fileURLWithPath: target.executablePath).lastPathComponent
        let fallback = target.name.lowercased()
        let candidate = raw.isEmpty ? fallback : raw.lowercased()
        let sanitized = candidate.map { scalar -> Character in
            if scalar.isLetter || scalar.isNumber {
                return scalar
            }
            return "-"
        }
        let compact = String(sanitized)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? "cli" : compact
    }
}
