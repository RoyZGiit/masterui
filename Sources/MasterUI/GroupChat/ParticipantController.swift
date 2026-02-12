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

    /// The full payload text injected, used for echo filtering during capture.
    private var injectedPayload: String = ""

    /// Scroll-invariant row where the injection started, used for buffer-based capture.
    private var injectionStartRow: Int = 0

    /// How many idle cycles we've retried capture waiting for real content.
    private var captureRetryCount: Int = 0

    /// Maximum retries before giving up on capturing a response.
    private let maxCaptureRetries: Int = 5

    /// Reference to the history store for saving after each response.
    private let historyStore: GroupChatHistoryStore

    /// Called after this controller posts a new AI response to the group.
    /// The coordinator uses this to notify other idle participants.
    var onDidPostResponse: (() -> Void)?

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
        lines.append("Reply if you have something meaningful to contribute. If you have nothing to add, reply with exactly \"[PASS]\" and nothing else.")

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
        guard let termView = TerminalViewCache.shared.terminalView(for: sessionID) else { return }
        let coordinator = TerminalViewCache.shared.coordinator(for: sessionID)

        lastSeenSequence = groupSession.sequence
        isProcessing = true
        injectedPayload = payload
        captureRetryCount = 0

        // Prepare the coordinator: flush pending turn, create a single user block,
        // and reset output tracking so per-line commits don't happen.
        coordinator?.prepareForProgrammaticInput(payload)

        // Suppress input tracking so that send(source:data:) doesn't create
        // per-line user blocks via commitInputLine.
        termView.suppressInputTracking = true
        termView.sendAsPaste(payload)

        // Small delay to let the terminal process the bracketed paste before sending Enter.
        // This fixes the issue where gemini shows "[Pasted Text: N lines]" without executing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            termView.send(txt: "\r")
            termView.suppressInputTracking = false

            // Record where to start reading the response buffer.
            self.injectionStartRow = termView.currentScrollInvariantRow()
        }
    }

    private func captureAndPost() {
        guard let session = cliSession,
              let termView = TerminalViewCache.shared.terminalView(for: sessionID) else {
            isProcessing = false
            return
        }

        // Read the terminal buffer from where injection output started.
        let rawOutput = termView.getBufferText(fromRow: injectionStartRow, excludePromptLine: true)
        let content = Self.cleanGroupChatResponse(rawOutput, payload: injectedPayload)

        if content.isEmpty {
            captureRetryCount += 1
            if captureRetryCount < maxCaptureRetries {
                // No meaningful content yet (e.g. TUI still rendering) — stay
                // in isProcessing and wait for the next idle cycle to retry.
                return
            }
            // Exhausted retries — give up on this turn.
            isProcessing = false
            return
        }

        isProcessing = false

        // PASS protocol: AI has nothing to add — skip posting and don't notify others.
        if Self.isPassResponse(content) {
            lastSeenSequence = groupSession.sequence
            autoResponseCount += 1
            return
        }

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

        // Notify coordinator so other idle AIs can pick up this response
        onDidPostResponse?()

        // Continue the conversation chain — check if there are more messages
        // accumulated while we were processing
        checkForNewMessages()
    }

    // MARK: - Response Cleaning

    /// Cleans raw terminal buffer output for group chat posting.
    /// Removes echoed payload lines and TUI chrome (box-drawing, block elements).
    static func cleanGroupChatResponse(_ text: String, payload: String) -> String {
        guard !text.isEmpty else { return "" }

        // Build a set of payload lines for echo removal.
        let payloadLines = Set(
            payload
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        let lines = text.components(separatedBy: .newlines)
        var filtered: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Drop lines that are pure TUI chrome (box-drawing / block chars).
            if isTUIChromeLine(trimmed) { continue }

            // Drop lines that are echoed payload.
            if !trimmed.isEmpty && payloadLines.contains(trimmed) { continue }

            filtered.append(line)
        }

        // Trim leading/trailing blank lines.
        while filtered.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            filtered.removeFirst()
        }
        while filtered.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            filtered.removeLast()
        }

        return filtered.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if the line consists entirely of TUI chrome characters
    /// (box-drawing, block elements) and spaces.
    private static func isTUIChromeLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let tuiChars = CharacterSet(charactersIn: "▄▀█▌▐░▒▓─│┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬ ")
        return line.unicodeScalars.allSatisfy { tuiChars.contains($0) }
    }

    /// Returns true if the cleaned response is a PASS signal (AI has nothing to add).
    /// Checks whether any line contains a PASS marker, since AI tools often emit
    /// thinking/exploration text alongside the signal (e.g. "✦ [PASS]").
    static func isPassResponse(_ content: String) -> Bool {
        let lower = content.lowercased()
        return lower.contains("[pass]") || lower.contains("\npass\n")
            || lower.hasSuffix("\npass") || lower == "pass"
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
