import Foundation
import Combine

// MARK: - ClosedGroupChat

/// Lightweight model representing a closed group chat in the recycle bin.
struct ClosedGroupChat: Identifiable {
    let id: UUID
    let title: String
    let participants: [String]
    let participantSessionIDs: [UUID]
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int

    init(from file: GroupChatHistoryFile) {
        self.id = file.chatID
        self.title = file.title
        self.participants = file.participants
        self.participantSessionIDs = file.resolvedParticipantSessionIDs
        self.createdAt = file.resolvedCreatedAt
        self.updatedAt = file.resolvedUpdatedAt
        self.messageCount = file.messages.count
    }
}

// MARK: - GroupChatManager

/// Manages the lifecycle of all group chat sessions.
class GroupChatManager: ObservableObject {
    @Published var groupChats: [GroupChatSession] = []
    @Published var activeGroupChatID: UUID?
    @Published var closedGroupChats: [ClosedGroupChat] = []

    private var coordinators: [UUID: GroupChatCoordinator] = [:]
    private var groupChatChangeCancellables: [UUID: AnyCancellable] = [:]

    var activeGroupChat: GroupChatSession? {
        guard let id = activeGroupChatID else { return nil }
        return groupChats.first { $0.id == id }
    }

    @discardableResult
    func createGroupChat(
        title: String,
        participantSessionIDs: [UUID],
        sessionManager: CLISessionManager,
        sessionID: UUID? = nil,
        createdAt: Date = Date(),
        messages: [GroupMessage] = []
    ) -> GroupChatSession {
        let session = GroupChatSession(
            id: sessionID ?? UUID(),
            title: title,
            participantSessionIDs: participantSessionIDs,
            createdAt: createdAt
        )
        session.messages = messages
        session.sequence = messages.count
        session.lastActivityDate = messages.last?.timestamp ?? createdAt
        session.hasUnreadActivity = false
        groupChats.append(session)
        observeGroupChatChanges(session)
        activeGroupChatID = session.id

        let coordinator = GroupChatCoordinator(
            groupSession: session,
            sessionManager: sessionManager
        )
        coordinator.setupControllers()
        coordinators[session.id] = coordinator
        refreshClosedGroupChats()

        return session
    }

    func closeGroupChat(id: UUID) {
        if let chat = groupChats.first(where: { $0.id == id }) {
            GroupChatHistoryStore.shared.save(chat)
        }
        coordinators.removeValue(forKey: id)
        groupChatChangeCancellables[id] = nil
        groupChats.removeAll { $0.id == id }
        if activeGroupChatID == id {
            activeGroupChatID = groupChats.first?.id
        }
        refreshClosedGroupChats()
    }

    func coordinator(for groupChatID: UUID) -> GroupChatCoordinator? {
        coordinators[groupChatID]
    }

    func focusGroupChat(_ id: UUID) {
        activeGroupChatID = id
        if let chat = groupChats.first(where: { $0.id == id }) {
            chat.hasUnreadActivity = false
        }
    }

    // MARK: - Recycle Bin

    func refreshClosedGroupChats() {
        let activeIDs = Set(groupChats.map { $0.id })
        closedGroupChats = GroupChatHistoryStore.shared.listAll()
            .filter { !activeIDs.contains($0.chatID) }
            .map { ClosedGroupChat(from: $0) }
    }

    func permanentlyDeleteClosedGroupChat(_ id: UUID) {
        GroupChatHistoryStore.shared.delete(id: id)
        closedGroupChats.removeAll { $0.id == id }
    }

    func canRestoreClosedGroupChat(_ id: UUID, sessionManager: CLISessionManager) -> Bool {
        guard let history = GroupChatHistoryStore.shared.load(id: id) else { return false }
        let participantIDs = history.resolvedParticipantSessionIDs
        guard participantIDs.count >= 2 else { return false }

        let activeSessionIDs = Set(sessionManager.sessions.map { $0.id })
        return participantIDs.allSatisfy { activeSessionIDs.contains($0) }
    }

    @discardableResult
    func restoreClosedGroupChat(_ id: UUID, sessionManager: CLISessionManager) -> Bool {
        if groupChats.contains(where: { $0.id == id }) {
            focusGroupChat(id)
            refreshClosedGroupChats()
            return true
        }

        guard let history = GroupChatHistoryStore.shared.load(id: id) else { return false }
        let participantIDs = history.resolvedParticipantSessionIDs
        guard participantIDs.count >= 2 else { return false }

        let activeSessionIDs = Set(sessionManager.sessions.map { $0.id })
        guard participantIDs.allSatisfy({ activeSessionIDs.contains($0) }) else { return false }

        _ = createGroupChat(
            title: history.title,
            participantSessionIDs: participantIDs,
            sessionManager: sessionManager,
            sessionID: history.chatID,
            createdAt: history.resolvedCreatedAt,
            messages: history.messages
        )
        refreshClosedGroupChats()
        return true
    }

    func clearAllClosedGroupChats() {
        for closed in closedGroupChats {
            GroupChatHistoryStore.shared.delete(id: closed.id)
        }
        closedGroupChats.removeAll()
    }

    // MARK: - Private

    private func observeGroupChatChanges(_ chat: GroupChatSession) {
        groupChatChangeCancellables[chat.id] = chat.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}
