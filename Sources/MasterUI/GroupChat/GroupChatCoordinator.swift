import Foundation
import Combine

// MARK: - GroupChatCoordinator

/// Orchestrates message routing between a group chat and its participant CLI sessions.
class GroupChatCoordinator: ObservableObject {
    let groupSession: GroupChatSession
    private var cancellables = Set<AnyCancellable>()
    private weak var sessionManager: CLISessionManager?

    /// Tracks which session IDs already had their response captured for the current round.
    private var capturedThisRound = Set<UUID>()

    /// Snapshot of block counts per session at the time we actually send (or flush) the payload,
    /// so we can identify the new assistant block.
    private var blockCountAtSend: [UUID: Int] = [:]

    /// Buffer for payloads that couldn't be delivered because the target session was busy
    /// (not in `waitingForInput`). Keyed by session ID. When the session becomes idle the
    /// buffered payload is automatically flushed.
    private var messageBuffer: [UUID: String] = [:]

    /// Tracks which sessions have actually had their payload delivered this round (either
    /// immediately or via buffer flush). Prevents premature response capture for buffered
    /// sessions that haven't received the message yet.
    private var sentThisRound = Set<UUID>()

    // MARK: - History File

    private static let groupChatDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui/groupchat")
    }()

    private var historyFileURL: URL {
        Self.groupChatDirectory.appendingPathComponent("\(groupSession.id.uuidString).txt")
    }

    init(groupSession: GroupChatSession, sessionManager: CLISessionManager) {
        self.groupSession = groupSession
        self.sessionManager = sessionManager
    }

    // MARK: - Send User Message

    /// Sends a user message to all participant CLIs with per-participant context.
    /// Sessions that are currently busy (not in `waitingForInput`) will have their
    /// payload buffered and automatically sent once they become idle.
    func sendUserMessage(_ text: String) {
        let userMessage = GroupMessage(
            source: .user,
            content: text
        )
        groupSession.appendMessage(userMessage)

        // Save history with the new user message
        saveHistoryToFile()

        // Reset per-round tracking state.
        capturedThisRound.removeAll()
        blockCountAtSend.removeAll()
        messageBuffer.removeAll()
        sentThisRound.removeAll()

        // Eagerly ensure each participant's terminal view exists in the cache —
        // views are normally created lazily when the session is first focused in
        // CLILayoutView, so a session that was never viewed would have no terminal
        // view and messages would silently fail to send.
        for sessionID in groupSession.participantSessionIDs {
            guard let session = sessionManager?.sessions.first(where: { $0.id == sessionID }) else {
                continue
            }
            let _ = TerminalViewCache.shared.getOrCreate(for: session, onStateChange: nil)
            groupSession.pendingResponses.insert(sessionID)
        }

        // Build and deliver (or buffer) the payload for each participant.
        for sessionID in groupSession.participantSessionIDs {
            guard let session = sessionManager?.sessions.first(where: { $0.id == sessionID }) else {
                continue
            }
            let payload = buildPayload(for: sessionID, userMessage: text)

            if session.state == .waitingForInput {
                // Session is idle — send immediately.
                sendPayload(payload, to: session)
            } else {
                // Session is busy — buffer until it becomes idle.
                messageBuffer[sessionID] = payload
            }
        }

        // Start monitoring for buffer flushes and response captures.
        startMonitoring()
    }

    // MARK: - Payload Delivery

    /// Sends a payload to a session's terminal and snapshots the block count so
    /// we can later identify the new assistant response.
    private func sendPayload(_ payload: String, to session: CLISession) {
        guard let termView = TerminalViewCache.shared.terminalView(for: session.id) else { return }
        blockCountAtSend[session.id] = session.history.blocks.count
        sentThisRound.insert(session.id)
        termView.sendAsPaste(payload)
        termView.send(txt: "\r")
    }

    /// Flushes the buffered payload for a session that just became idle.
    private func flushBuffer(for session: CLISession) {
        guard let payload = messageBuffer.removeValue(forKey: session.id) else { return }
        sendPayload(payload, to: session)
    }

    // MARK: - Response Monitoring

    /// Observe each participant's session state to capture responses.
    /// When a session transitions to `waitingForInput`:
    ///  1. If there is a buffered payload for it, flush the buffer (send the message).
    ///  2. Otherwise, if the message was already sent, capture the assistant response.
    func startMonitoring() {
        // Cancel previous subscriptions to avoid duplicates
        cancellables.removeAll()

        for sessionID in groupSession.participantSessionIDs {
            guard let session = sessionManager?.sessions.first(where: { $0.id == sessionID }) else {
                continue
            }

            session.$state
                .dropFirst() // skip current value
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    guard state == .waitingForInput else { return }

                    if self.messageBuffer[sessionID] != nil {
                        // Session just became idle — flush the buffered payload.
                        self.flushBuffer(for: session)
                    } else if self.sentThisRound.contains(sessionID) {
                        // Payload was already delivered — capture the response.
                        self.captureResponse(for: session)
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// Capture the latest assistant response from a session's history.
    private func captureResponse(for session: CLISession) {
        let sessionID = session.id

        // Avoid double-capture in the same round
        guard !capturedThisRound.contains(sessionID) else { return }
        guard groupSession.pendingResponses.contains(sessionID) else { return }

        // Find the assistant block that appeared after we sent the message
        let startIndex = blockCountAtSend[sessionID] ?? 0
        let newBlocks = session.history.blocks.dropFirst(startIndex)
        guard let assistantBlock = newBlocks.last(where: { $0.role == .assistant }) else {
            return
        }

        let content = assistantBlock.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        capturedThisRound.insert(sessionID)

        let aiMessage = GroupMessage(
            source: .ai(
                name: session.target.name,
                sessionID: sessionID,
                colorHex: session.target.colorHex
            ),
            content: content
        )

        groupSession.appendMessage(aiMessage)
        groupSession.markResponseReceived(sessionID: sessionID)

        // Save history with the new AI response
        saveHistoryToFile()

        // Stop monitoring once all responses are in
        if groupSession.allResponsesReceived {
            cancellables.removeAll()
        }
    }

    // MARK: - History Persistence

    /// Saves the full group chat conversation to a human-readable text file.
    func saveHistoryToFile() {
        let fm = FileManager.default
        let dir = Self.groupChatDirectory

        // Ensure directory exists
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let participantNames = resolveParticipantNames()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = []
        lines.append("=== Group Chat: \(groupSession.title) ===")
        lines.append("Participants: \(participantNames.values.sorted().joined(separator: ", "))")
        lines.append("History file: \(historyFileURL.path)")
        lines.append("Created: \(dateFormatter.string(from: groupSession.createdAt))")
        lines.append("")

        // Group messages into rounds (a round starts with each user message)
        var roundNumber = 0
        for message in groupSession.messages {
            switch message.source {
            case .user:
                roundNumber += 1
                lines.append("--- Round \(roundNumber) ---")
                lines.append("[User]: \(message.content)")
            case .ai(let name, _, _):
                lines.append("[\(name)]: \(message.content)")
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: historyFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Per-Participant Payload

    /// Builds a personalized payload for a specific participant that includes group chat
    /// context, the history file path, recent messages from other participants, and the
    /// user's new message.
    func buildPayload(for sessionID: UUID, userMessage: String) -> String {
        let names = resolveParticipantNames()
        let myName = names[sessionID] ?? "AI"
        let otherNames = groupSession.participantSessionIDs
            .filter { $0 != sessionID }
            .compactMap { names[$0] }

        var lines: [String] = []

        // Group chat header
        lines.append("[Group Chat] You are \"\(myName)\" in a group chat with: \(otherNames.joined(separator: ", ")).")
        lines.append("The full conversation history is saved at: \(historyFileURL.path)")
        lines.append("You can read this file to see the complete chat history.")

        // Include last round's responses from other participants
        let otherResponses = groupSession.lastRoundAIMessages.filter {
            if case .ai(_, let sid, _) = $0.source {
                return sid != sessionID
            }
            return false
        }
        if !otherResponses.isEmpty {
            lines.append("")
            lines.append("Recent messages from other participants:")
            for msg in otherResponses {
                lines.append("[\(msg.source.displayName)]: \(msg.content)")
            }
        }

        // User's new message
        lines.append("")
        lines.append("User's new message:")
        lines.append(userMessage)

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Resolves participant session IDs to their display names.
    private func resolveParticipantNames() -> [UUID: String] {
        guard let sessionManager = sessionManager else { return [:] }
        return groupSession.participantNames(sessionManager: sessionManager)
    }
}
