import Foundation
import Combine

// MARK: - ParticipantController

/// Per-AI state machine that independently manages message fetching, response capture,
/// and posting back to the group chat. Each AI participant gets its own controller.
class ParticipantController: ObservableObject {
    let sessionID: UUID
    let groupSession: GroupChatSession
    weak var cliSession: CLISession?
    weak var sessionManager: CLISessionManager?

    /// The sequence number this AI has processed up to.
    private var lastSeenSequence: Int = 0

    /// Number of automatic responses this AI has made (safety cap).
    private var autoResponseCount: Int = 0

    /// Maximum automatic responses before stopping (safety cap).
    var maxAutoResponses: Int = 10

    /// Whether this AI is currently processing a response.
    @Published var isProcessing: Bool = false

    private var cancellables = Set<AnyCancellable>()

    /// Block count snapshot at the time we sent the payload, so we can
    /// identify the new assistant response.
    private var blockCountAtSend: Int = 0

    /// Reference to the history store for saving after each response.
    private let historyStore: GroupChatHistoryStore

    init(
        sessionID: UUID,
        groupSession: GroupChatSession,
        cliSession: CLISession?,
        sessionManager: CLISessionManager?,
        historyStore: GroupChatHistoryStore = .shared
    ) {
        self.sessionID = sessionID
        self.groupSession = groupSession
        self.cliSession = cliSession
        self.sessionManager = sessionManager
        self.historyStore = historyStore
    }

    // MARK: - Start Observing

    /// Begin observing the CLI session's state to detect when it becomes idle.
    func startObserving() {
        cliSession?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard state == .waitingForInput else { return }
                self?.onSessionBecameIdle()
            }
            .store(in: &cancellables)
    }

    // MARK: - Core Loop

    /// Called when the underlying CLI session transitions to idle (waitingForInput).
    private func onSessionBecameIdle() {
        if isProcessing {
            // Just finished processing — capture the response first.
            captureAndPost()
            return
        }

        // Not processing — check for new messages.
        checkForNewMessages()
    }

    /// Checks for new group messages and injects a payload if there are any.
    /// Called both from the idle observer and externally when the user sends a message.
    func checkForNewMessages() {
        // Safety cap
        guard autoResponseCount < maxAutoResponses else { return }

        // Get messages since last seen
        let newMessages = groupSession.messages(after: lastSeenSequence)

        // Only react to messages from others (other AIs or the user)
        let relevantNew = newMessages.filter { msg in
            if case .ai(_, let sid, _) = msg.source {
                return sid != sessionID
            }
            return true // user and system messages are always relevant
        }

        guard !relevantNew.isEmpty else { return }

        // Build and inject the payload
        let payload = buildPayload(newMessages: relevantNew)
        injectPayload(payload)
    }

    // MARK: - Payload Construction

    private func buildPayload(newMessages: [GroupMessage]) -> String {
        var lines: [String] = []

        let myName = cliSession?.target.name ?? "AI"
        let otherNames = groupSession.participantSessionIDs
            .filter { $0 != sessionID }
            .compactMap { resolveParticipantName(sessionID: $0) }

        let historyPath = historyStore.historyFilePath(for: groupSession)

        // Identity + context
        lines.append("[Group Chat] You are \"\(myName)\" in a discussion with: \(otherNames.joined(separator: ", ")).")
        lines.append("Full history: \(historyPath)")
        lines.append("")

        // New messages
        lines.append("New messages since your last response:")
        for msg in newMessages {
            lines.append("[\(msg.source.displayName)]: \(msg.content)")
        }
        lines.append("")
        lines.append("Please respond to the above. If you truly have nothing to add, keep your response very brief.")

        return lines.joined(separator: "\n")
    }

    /// Resolves a participant name by checking the session manager first,
    /// then falling back to group messages.
    private func resolveParticipantName(sessionID: UUID) -> String? {
        if let session = sessionManager?.sessions.first(where: { $0.id == sessionID }) {
            return session.target.name
        }
        for msg in groupSession.messages {
            if case .ai(let name, let sid, _) = msg.source, sid == sessionID {
                return name
            }
        }
        return nil
    }

    // MARK: - Inject & Capture

    private func injectPayload(_ payload: String) {
        guard let session = cliSession,
              let termView = TerminalViewCache.shared.terminalView(for: sessionID) else { return }

        blockCountAtSend = session.history.blocks.count
        lastSeenSequence = groupSession.sequence
        isProcessing = true

        termView.sendAsPaste(payload)
        termView.send(txt: "\r")
    }

    private func captureAndPost() {
        guard let session = cliSession else {
            isProcessing = false
            return
        }

        let newBlocks = session.history.blocks.dropFirst(blockCountAtSend)
        guard let block = newBlocks.last(where: { $0.role == .assistant }) else {
            isProcessing = false
            return
        }

        let content = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        isProcessing = false

        guard !content.isEmpty else { return }

        // Post the response back to the group
        let aiMessage = GroupMessage(
            source: .ai(
                name: session.target.name,
                sessionID: sessionID,
                colorHex: session.target.colorHex
            ),
            content: content
        )
        groupSession.appendMessage(aiMessage)

        // Update cursor to include our own response
        lastSeenSequence = groupSession.sequence
        autoResponseCount += 1

        // Persist history
        historyStore.save(groupSession)
    }

    // MARK: - User Control

    /// Resets the controller for a new conversation round initiated by the user.
    func reset() {
        autoResponseCount = 0
        lastSeenSequence = groupSession.sequence
        isProcessing = false
        cancellables.removeAll()
    }

    /// Stops all observation and processing.
    func stop() {
        isProcessing = false
        cancellables.removeAll()
    }
}
