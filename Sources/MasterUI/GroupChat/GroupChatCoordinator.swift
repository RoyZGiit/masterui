import Foundation
import Combine

// MARK: - GroupChatCoordinator

/// Lightweight container that manages a collection of ParticipantControllers.
/// Each participant has its own independent state machine for message processing.
class GroupChatCoordinator: ObservableObject {
    let groupSession: GroupChatSession
    weak var sessionManager: CLISessionManager?

    /// Per-participant controllers keyed by session ID.
    @Published var controllers: [UUID: ParticipantController] = [:]

    private let historyStore: GroupChatHistoryStore

    /// Whether any participant is currently processing a response.
    var isConversationActive: Bool {
        controllers.values.contains { $0.isProcessing }
    }

    init(
        groupSession: GroupChatSession,
        sessionManager: CLISessionManager,
        historyStore: GroupChatHistoryStore = .shared
    ) {
        self.groupSession = groupSession
        self.sessionManager = sessionManager
        self.historyStore = historyStore
    }

    // MARK: - Setup Controllers

    /// Creates a ParticipantController for each participant and starts observing.
    func setupControllers() {
        guard let sessionManager = sessionManager else { return }

        for sessionID in groupSession.participantSessionIDs {
            guard controllers[sessionID] == nil else { continue }
            guard let session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { continue }

            let controller = ParticipantController(
                sessionID: sessionID,
                groupSession: groupSession,
                cliSession: session,
                sessionManager: sessionManager,
                historyStore: historyStore
            )
            controllers[sessionID] = controller
            controller.startObserving()
        }
    }

    // MARK: - Send User Message

    /// Appends a user message to the group session and triggers idle AIs to check.
    func sendUserMessage(_ text: String) {
        let message = GroupMessage(source: .user, content: text)
        groupSession.appendMessage(message)
        historyStore.save(groupSession)

        // Ensure each participant's terminal view exists in the cache
        guard let sessionManager = sessionManager else { return }
        for sessionID in groupSession.participantSessionIDs {
            guard let session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { continue }
            let _ = TerminalViewCache.shared.getOrCreate(for: session, onStateChange: nil)
        }

        // Trigger idle AIs to check for new messages immediately.
        // Busy AIs will pick up the new message when they become idle.
        for (_, controller) in controllers {
            if controller.cliSession?.state == .waitingForInput {
                controller.checkForNewMessages()
            }
        }
    }

    // MARK: - Global Control

    /// Stops all participant controllers.
    func stopAll() {
        for (_, controller) in controllers {
            controller.stop()
        }
    }

    /// Resets all participant controllers for a fresh conversation round.
    func resetAll() {
        for (_, controller) in controllers {
            controller.reset()
        }
    }
}
