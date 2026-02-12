import Foundation

// MARK: - GroupChatManager

/// Manages the lifecycle of all group chat sessions.
class GroupChatManager: ObservableObject {
    @Published var groupChats: [GroupChatSession] = []
    @Published var activeGroupChatID: UUID?

    private var coordinators: [UUID: GroupChatCoordinator] = [:]

    var activeGroupChat: GroupChatSession? {
        guard let id = activeGroupChatID else { return nil }
        return groupChats.first { $0.id == id }
    }

    @discardableResult
    func createGroupChat(
        title: String,
        participantSessionIDs: [UUID],
        sessionManager: CLISessionManager
    ) -> GroupChatSession {
        let session = GroupChatSession(
            title: title,
            participantSessionIDs: participantSessionIDs
        )
        groupChats.append(session)
        activeGroupChatID = session.id

        let coordinator = GroupChatCoordinator(
            groupSession: session,
            sessionManager: sessionManager
        )
        coordinators[session.id] = coordinator

        return session
    }

    func closeGroupChat(id: UUID) {
        coordinators.removeValue(forKey: id)
        groupChats.removeAll { $0.id == id }
        if activeGroupChatID == id {
            activeGroupChatID = groupChats.first?.id
        }
    }

    func coordinator(for groupChatID: UUID) -> GroupChatCoordinator? {
        coordinators[groupChatID]
    }

    func focusGroupChat(_ id: UUID) {
        activeGroupChatID = id
    }
}
