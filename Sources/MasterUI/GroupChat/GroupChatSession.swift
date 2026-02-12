import Foundation

// MARK: - GroupChatSession

/// Represents a single group chat where multiple CLI sessions participate.
class GroupChatSession: ObservableObject, Identifiable {
    let id: UUID
    let createdAt: Date

    @Published var title: String
    @Published var participantSessionIDs: [UUID]
    @Published var messages: [GroupMessage]

    /// Message sequence number, incremented on each append.
    @Published var sequence: Int = 0

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
    }

    /// Returns all messages after the given sequence number.
    func messages(after afterSequence: Int) -> [GroupMessage] {
        let startIndex = afterSequence
        guard startIndex < messages.count else { return [] }
        return Array(messages[startIndex...])
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

}
