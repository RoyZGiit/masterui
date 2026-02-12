import Foundation

// MARK: - GroupChatSession

/// Represents a single group chat where multiple CLI sessions participate.
class GroupChatSession: ObservableObject, Identifiable {
    let id: UUID
    let createdAt: Date

    @Published var title: String
    @Published var participantSessionIDs: [UUID]
    @Published var messages: [GroupMessage]
    @Published var pendingResponses: Set<UUID>

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
        self.pendingResponses = []
        self.createdAt = createdAt
    }

    func addParticipant(_ sessionID: UUID) {
        guard !participantSessionIDs.contains(sessionID) else { return }
        participantSessionIDs.append(sessionID)
    }

    func removeParticipant(_ sessionID: UUID) {
        participantSessionIDs.removeAll { $0 == sessionID }
        pendingResponses.remove(sessionID)
    }

    func appendMessage(_ message: GroupMessage) {
        messages.append(message)
    }

    func markResponseReceived(sessionID: UUID) {
        pendingResponses.remove(sessionID)
    }

    var allResponsesReceived: Bool {
        pendingResponses.isEmpty
    }

    /// Returns participant display names by resolving session IDs through the session manager.
    func participantNames(sessionManager: CLISessionManager) -> [UUID: String] {
        var names: [UUID: String] = [:]
        for sessionID in participantSessionIDs {
            if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                names[sessionID] = session.target.name
            }
        }
        return names
    }

    /// Returns the AI messages from the most recent round (after the last user message).
    var lastRoundAIMessages: [GroupMessage] {
        guard let lastUserIndex = messages.lastIndex(where: {
            if case .user = $0.source { return true }
            return false
        }) else {
            return []
        }
        return Array(messages.suffix(from: messages.index(after: lastUserIndex)))
            .filter {
                if case .ai = $0.source { return true }
                return false
            }
    }
}
