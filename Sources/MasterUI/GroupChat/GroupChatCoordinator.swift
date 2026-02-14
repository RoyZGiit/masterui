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

    /// True when all participants have PASSed at least once since the last real message.
    @Published var isStalled: Bool = false

    /// Tracks which participants have PASSed since the last real message.
    private var participantPassState: [UUID: Bool] = [:]

    private let historyStore: GroupChatHistoryStore
    private var messageCancellable: AnyCancellable?
    private var participantCancellable: AnyCancellable?

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
        syncControllersToParticipants()
        startParticipantSync()
        startListening()
    }

    private func startParticipantSync() {
        participantCancellable = groupSession.$participantSessionIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncControllersToParticipants()
            }
    }

    func syncControllersToParticipants() {
        guard let sessionManager = sessionManager else { return }
        let desiredIDs = Set(groupSession.participantSessionIDs)

        let removedIDs = controllers.keys.filter { !desiredIDs.contains($0) }
        for sessionID in removedIDs {
            controllers[sessionID]?.shutdown()
            controllers.removeValue(forKey: sessionID)
            participantPassState.removeValue(forKey: sessionID)
        }

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
            controller.onPassStateChanged = { [weak self] sid, didPass in
                self?.handlePassStateChange(sessionID: sid, didPass: didPass)
            }
            participantPassState[sessionID] = false
            controllers[sessionID] = controller
            controller.startObserving()
        }
    }

    // MARK: - Event Subscription

    /// Subscribes to the group session's message publisher so that idle controllers
    /// are notified immediately when a new message is posted (no polling delay).
    private func startListening() {
        messageCancellable = groupSession.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.deliverMessage(chatID: self.groupSession.id, event: event)
            }
    }

    /// Fan-out delivery for a newly appended group chat message.
    /// Every participant (except the poster) receives a delivery signal for this chat.
    private func deliverMessage(chatID: UUID, event: GroupChatSession.MessageEvent) {
        guard chatID == groupSession.id else { return }

        // Determine which session posted so we can skip it.
        let posterSessionID: UUID?
        if case .ai(_, let sid, _) = event.message.source {
            posterSessionID = sid
        } else {
            posterSessionID = nil
        }

        for (sessionID, controller) in controllers {
            guard sessionID != posterSessionID else { continue }
            controller.deliverMessage(sequence: event.sequence)
        }
    }

    // MARK: - Stall Detection

    private func handlePassStateChange(sessionID: UUID, didPass: Bool) {
        if didPass {
            participantPassState[sessionID] = true
        } else {
            // Real response — reset all PASS tracking
            for key in participantPassState.keys {
                participantPassState[key] = false
            }
            isStalled = false
            return
        }

        // Check if ALL participants have now PASSed
        let allPassed = !participantPassState.isEmpty
            && participantPassState.values.allSatisfy { $0 }
        if allPassed && !isStalled {
            isStalled = true
        }
    }

    // MARK: - Send User Message

    /// Appends a user message to the group session and triggers idle AIs to check.
    func sendUserMessage(_ text: String) {
        // Reset stall state — user is re-engaging
        isStalled = false
        for key in participantPassState.keys {
            participantPassState[key] = false
        }

        let message = GroupMessage(source: .user, content: text)
        groupSession.appendMessage(message)
        historyStore.save(groupSession)

        // Ensure each participant's terminal view exists in the cache.
        // The messagePublisher subscription handles notifying idle controllers.
        guard let sessionManager = sessionManager else { return }
        for sessionID in groupSession.participantSessionIDs {
            guard let session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { continue }
            let _ = TerminalViewCache.shared.getOrCreate(for: session, onStateChange: nil)
        }
    }

    // MARK: - Global Control

    /// Stops all participant controllers' current work while keeping polling alive.
    func stopAll() {
        for (_, controller) in controllers {
            controller.stop()
        }
    }

    /// Fully stops message subscription and participant polling.
    /// Use only when the group chat is being closed.
    func shutdown() {
        messageCancellable?.cancel()
        messageCancellable = nil
        participantCancellable?.cancel()
        participantCancellable = nil
        for (_, controller) in controllers {
            controller.shutdown()
        }
    }

    /// Resets all participant controllers for a fresh conversation round.
    func resetAll() {
        for (_, controller) in controllers {
            controller.reset()
        }
    }

    // MARK: - Realtime Events

    /// Applies a single realtime event from backend streaming.
    func receiveRealtimeEvent(_ event: GroupChatRealtimeEvent) {
        groupSession.applyRealtimeEvent(event)
    }

    /// Applies a batch of realtime events from backend replay/streaming.
    func receiveRealtimeEvents(_ events: [GroupChatRealtimeEvent]) {
        for event in events {
            groupSession.applyRealtimeEvent(event)
        }
    }

    deinit {
        shutdown()
    }

}
