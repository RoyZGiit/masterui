import Foundation
import Combine

// MARK: - Loop Debug States

enum InputLoopState: String {
    case stopped = "stopped"
    case idle = "idle"           // timer running, skipped (isProcessing or not stably idle)
    case polling = "polling"     // actively checking for new messages
    case injecting = "injecting" // building payload and injecting into terminal
}

enum OutputLoopState: String {
    case stopped = "stopped"
    case idle = "idle"           // timer running, skipped (not processing or not stably idle)
    case polling = "polling"     // actively polling for output
    case capturing = "capturing" // reading terminal buffer and posting
}

struct ParticipantDebugStatus {
    var inputLoop: InputLoopState = .stopped
    var outputLoop: OutputLoopState = .stopped
    var lastSeenSequence: Int = 0
    var groupSequence: Int = 0
    var isProcessing: Bool = false
    var isStableIdle: Bool = false
    var consecutivePassCount: Int = 0
}

// MARK: - Debug Event

enum DebugEventType: String {
    case messageInjected = "injected"
    case outputCaptured = "captured"
    case pollDecision = "poll"
    case backendOutput = "backend"
    case passDetected = "PASS"
    case waitingForInput = "waiting"
    case stableIdleReached = "stableIdle"
    case noNewMessages = "noNew"
    case retryScheduled = "retry"
    case deliveryFailed = "deliveryFail"
}

struct DebugEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: DebugEventType
    let detail: String
}

// MARK: - ParticipantController

/// Per-AI state machine that independently manages message fetching, response capture,
/// and posting back to the group chat. Each AI participant gets its own controller.
class ParticipantController: ObservableObject {
    private struct TurnContext {
        let token: UUID
        let turnID: UUID
        let runID: String
        let agentID: String
        let injectedAtSequence: Int
        let payload: String
        var injectionStartRow: Int
    }

    private struct PendingDelivery {
        let id: UUID
        let payload: String
        let runID: String
        let agentID: String
        let relevantMessages: [GroupMessage]
        let enqueuedAt: Date
        var attemptCount: Int = 0
        var lastAttemptAt: Date?
        var lastFailureReason: String?
    }

    private static let retryBaseInterval: TimeInterval = 1.0
    private static let retryMaxInterval: TimeInterval = 8.0

    let sessionID: UUID
    let groupSession: GroupChatSession
    weak var cliSession: CLISession?
    weak var sessionManager: CLISessionManager?

    /// The sequence number this AI has processed up to.
    private var lastSeenSequence: Int = 0

    /// Whether this AI is currently processing a response.
    @Published var isProcessing: Bool = false

    /// Debug status for the loop state display.
    @Published var debugStatus = ParticipantDebugStatus()

    /// Recent debug events for the debug panel (capped at 50).
    @Published var debugEvents: [DebugEvent] = []

    /// Number of consecutive PASS responses from this participant.
    @Published var consecutivePassCount: Int = 0

    /// Callback invoked when a PASS is detected or a real response is posted.
    /// The coordinator uses this to track stall state.
    var onPassStateChanged: ((_ sessionID: UUID, _ didPass: Bool) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    /// Reference to the history store for saving after each response.
    private let historyStore: GroupChatHistoryStore

    /// Stable-idle detection: set when state becomes .waitingForInput, cleared otherwise.
    private var waitingForInputSince: Date?

    /// Minimum time the session must be continuously idle before we act.
    private let stableIdleThreshold: TimeInterval = 1.0

    /// Polling frequency for both output capture and input check loops.
    private let pollInterval: TimeInterval = 0.5

    /// Polling timers.
    private var outputPollTimer: Timer?
    private var inputPollTimer: Timer?

    /// State for the active injected turn. Guards against stale async callbacks.
    private var activeTurn: TurnContext?
    private var postedTurnIDs = Set<UUID>()
    private var postedFingerprints = Set<String>()

    /// Pending delivery waiting to be injected (capacity = 1, replaced by newer payloads).
    private var pendingDelivery: PendingDelivery?
    /// Latest group sequence announced by coordinator fan-out.
    private var pendingFanoutSequence: Int?
    private var retryTimer: Timer?
    private var lastLoggedRawOutput: String = ""

    private static func nextEventID() -> String {
        "evt_\(UUID().uuidString.lowercased())"
    }

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

    /// Returns true if the session has been stably idle for at least `stableIdleThreshold`.
    private var isStableIdle: Bool {
        guard let since = waitingForInputSince else { return false }
        return Date().timeIntervalSince(since) >= stableIdleThreshold
    }

    /// Refreshes the published debug status snapshot.
    private func refreshDebugStatus(
        inputLoop: InputLoopState? = nil,
        outputLoop: OutputLoopState? = nil
    ) {
        var s = debugStatus
        if let il = inputLoop { s.inputLoop = il }
        if let ol = outputLoop { s.outputLoop = ol }
        s.lastSeenSequence = lastSeenSequence
        s.groupSequence = groupSession.sequence
        s.isProcessing = isProcessing
        s.isStableIdle = isStableIdle
        debugStatus = s
    }

    /// Appends a debug event, capping the array at 50 entries.
    private func logDebugEvent(_ type: DebugEventType, detail: String) {
        let event = DebugEvent(timestamp: Date(), type: type, detail: detail)
        debugEvents.append(event)
        if debugEvents.count > 50 {
            debugEvents.removeFirst(debugEvents.count - 50)
        }
    }

    private func logLoopDecision(
        category: String,
        decision: String,
        detail: String,
        output: String? = nil,
        metadata: [String: String] = [:]
    ) {
        logDebugEvent(.pollDecision, detail: "\(category):\(decision) \(detail)")
        GroupChatDebugLogger.shared.log(
            groupSession: groupSession,
            participantSessionID: sessionID,
            category: category,
            decision: decision,
            detail: detail,
            output: output,
            metadata: metadata
        )
    }

    private func logBackendOutputDelta(_ rawOutput: String, runID: String, agentID: String) {
        let delta: String
        if rawOutput.hasPrefix(lastLoggedRawOutput) {
            delta = String(rawOutput.dropFirst(lastLoggedRawOutput.count))
        } else if lastLoggedRawOutput.hasPrefix(rawOutput) {
            delta = ""
        } else {
            delta = rawOutput
        }

        if delta.isEmpty {
            logLoopDecision(
                category: "output_capture",
                decision: "no_delta",
                detail: "raw=\(rawOutput.count)",
                metadata: ["run_id": runID, "agent_id": agentID]
            )
        } else {
            logDebugEvent(.backendOutput, detail: "delta \(delta.count) chars")
            logLoopDecision(
                category: "backend_output",
                decision: "delta",
                detail: "chars=\(delta.count)",
                output: delta,
                metadata: ["run_id": runID, "agent_id": agentID]
            )
        }
        lastLoggedRawOutput = rawOutput
    }

    private func agentIdentifier() -> String {
        let labels = sessionManager.map { groupSession.participantDisplayNames(sessionManager: $0) } ?? [:]
        return labels[sessionID] ?? cliSession?.target.name ?? sessionID.uuidString
    }

    private func emitStatus(
        runID: String,
        agentID: String,
        status: GroupChatAgentStatus,
        phaseText: String? = nil
    ) {
        groupSession.applyRealtimeEvent(
            .agentStatus(
                GroupChatAgentStatusEvent(
                    eventId: Self.nextEventID(),
                    runId: runID,
                    agentId: agentID,
                    status: status,
                    phaseText: phaseText,
                    ts: Date(),
                    ephemeral: true,
                    persist: false
                )
            )
        )
    }

    private func emitEphemeralMessage(
        runID: String,
        agentID: String,
        kind: GroupChatEphemeralKind,
        text: String,
        meta: [String: String] = [:]
    ) {
        groupSession.applyRealtimeEvent(
            .ephemeralMessage(
                GroupChatEphemeralMessageEvent(
                    eventId: Self.nextEventID(),
                    runId: runID,
                    agentId: agentID,
                    kind: kind,
                    text: text,
                    meta: meta,
                    ts: Date(),
                    ephemeral: true,
                    persist: false
                )
            )
        )
    }

    // MARK: - Start Observing

    /// Begin observing the CLI session's state to track stable-idle timing.
    func startObserving() {
        // Start from the current sequence so restored chats don't replay old turns.
        lastSeenSequence = groupSession.sequence
        logLoopDecision(
            category: "lifecycle",
            decision: "start_observing",
            detail: "last_seen=\(lastSeenSequence)"
        )

        cliSession?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .waitingForInput {
                    if self.waitingForInputSince == nil {
                        self.waitingForInputSince = Date()
                    }
                } else {
                    self.waitingForInputSince = nil
                }
                self.logDebugEvent(.waitingForInput, detail: "state=\(state.rawValue)")
                self.logLoopDecision(
                    category: "session_state",
                    decision: "state_update",
                    detail: state.rawValue
                )
                self.drainPendingFanoutIfReady(forceStableIdle: false)
            }
            .store(in: &cancellables)

        startOutputPolling()
        startInputPolling()
        refreshDebugStatus(inputLoop: .idle, outputLoop: .idle)
    }

    // MARK: - Polling

    private func startOutputPolling() {
        outputPollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pollOutput()
            }
        }
        // Use .common mode so timers fire during scrolling / modal sheets too.
        RunLoop.main.add(timer, forMode: .common)
        outputPollTimer = timer
    }

    private func pollOutput() {
        guard isProcessing, isStableIdle else {
            let reason = !isProcessing ? "not_processing" : "not_stable_idle"
            logLoopDecision(category: "output_poll", decision: "skip", detail: reason)
            refreshDebugStatus(outputLoop: .idle)
            return
        }

        logLoopDecision(category: "output_poll", decision: "run", detail: "capturing")
        refreshDebugStatus(outputLoop: .polling)

        captureAndPost()
    }

    private func startInputPolling() {
        inputPollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pollInput()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        inputPollTimer = timer
    }

    private func pollInput() {
        drainPendingFanoutIfReady(forceStableIdle: true)

        guard !isProcessing, isStableIdle else {
            let reason = isProcessing ? "is_processing" : "not_stable_idle"
            logLoopDecision(category: "input_poll", decision: "skip", detail: reason)
            refreshDebugStatus(inputLoop: .idle)
            return
        }
        logDebugEvent(.stableIdleReached, detail: "checking for messages")
        logLoopDecision(category: "input_poll", decision: "run", detail: "stable_idle_reached")
        refreshDebugStatus(inputLoop: .polling)
        checkForNewMessages()
    }

    // MARK: - Core Loop

    /// Checks for new group messages and injects a payload if there are any.
    /// Called both from the idle observer and externally when the user sends a message.
    func checkForNewMessages() {
        guard !isProcessing else {
            logLoopDecision(category: "check_messages", decision: "skip", detail: "already_processing")
            refreshDebugStatus(inputLoop: .idle)
            return
        }

        refreshDebugStatus(inputLoop: .polling)

        // Get messages since last seen
        let newMessages = groupSession.messages(after: lastSeenSequence)

        // Only react to messages from others (other AIs or the user)
        let relevantNew = newMessages.filter { msg in
            if case .ai(_, let sid, _) = msg.source {
                return sid != sessionID
            }
            return true // user and system messages are always relevant
        }
        logLoopDecision(
            category: "check_messages",
            decision: "evaluated",
            detail: "new=\(newMessages.count) relevant=\(relevantNew.count) seen=\(lastSeenSequence) seq=\(groupSession.sequence)"
        )

        guard !relevantNew.isEmpty else {
            // No relevant messages, but advance cursor past non-relevant ones
            // (e.g. our own AI responses) to avoid re-checking them each poll.
            if !newMessages.isEmpty {
                lastSeenSequence = groupSession.sequence
                logLoopDecision(
                    category: "check_messages",
                    decision: "advance_cursor",
                    detail: "self_only_messages seq=\(lastSeenSequence)"
                )
            }
            logDebugEvent(.noNewMessages, detail: "seq \(groupSession.sequence), seen \(lastSeenSequence)")
            logLoopDecision(
                category: "check_messages",
                decision: "no_relevant_messages",
                detail: "idle"
            )
            refreshDebugStatus(inputLoop: .idle)
            return
        }

        // Build and inject the payload
        refreshDebugStatus(inputLoop: .injecting)
        let payload = buildPayload(newMessages: relevantNew)
        let runID = UUID().uuidString.lowercased()
        let agentID = agentIdentifier()
        emitStatus(runID: runID, agentID: agentID, status: .queued, phaseText: "queued \(relevantNew.count) message(s)")
        emitEphemeralMessage(
            runID: runID,
            agentID: agentID,
            kind: .thought,
            text: "Preparing prompt from \(relevantNew.count) new message(s)"
        )
        logDebugEvent(.messageInjected, detail: "\(relevantNew.count) msg(s), seq \(groupSession.sequence)")
        logLoopDecision(
            category: "delivery",
            decision: "enqueue",
            detail: "relevant=\(relevantNew.count) payload=\(payload.count)chars",
            metadata: ["run_id": runID, "agent_id": agentID]
        )
        enqueueDelivery(payload: payload, runID: runID, agentID: agentID, relevantMessages: relevantNew)
    }

    /// Called by GroupChatCoordinator for chat-level fan-out delivery.
    /// If this participant is busy, the signal is queued and replayed once it is stably idle.
    func deliverMessage(sequence: Int) {
        if let existing = pendingFanoutSequence {
            pendingFanoutSequence = max(existing, sequence)
        } else {
            pendingFanoutSequence = sequence
        }
        drainPendingFanoutIfReady(forceStableIdle: false)
    }

    // MARK: - Delivery Queue & Retry

    private func enqueueDelivery(payload: String, runID: String, agentID: String, relevantMessages: [GroupMessage]) {
        // Cancel any pending retry — the new payload supersedes it.
        retryTimer?.invalidate()
        retryTimer = nil

        pendingDelivery = PendingDelivery(
            id: UUID(),
            payload: payload,
            runID: runID,
            agentID: agentID,
            relevantMessages: relevantMessages,
            enqueuedAt: Date()
        )
        attemptDelivery()
    }

    private func attemptDelivery() {
        guard var delivery = pendingDelivery else { return }

        delivery.attemptCount += 1
        delivery.lastAttemptAt = Date()
        pendingDelivery = delivery
        logLoopDecision(
            category: "delivery",
            decision: "attempt",
            detail: "attempt=\(delivery.attemptCount)",
            metadata: ["run_id": delivery.runID, "agent_id": delivery.agentID]
        )

        guard TerminalViewCache.shared.terminalView(for: sessionID) != nil else {
            delivery.lastFailureReason = "terminalView unavailable"
            pendingDelivery = delivery
            logDebugEvent(.deliveryFailed, detail: "terminal view unavailable")
            logLoopDecision(
                category: "delivery",
                decision: "terminal_unavailable",
                detail: "retry_scheduled",
                metadata: ["run_id": delivery.runID, "agent_id": delivery.agentID]
            )
            scheduleRetry()
            return
        }

        // Terminal is available — deliver now.
        let payload = delivery.payload
        let runID = delivery.runID
        let agentID = delivery.agentID
        pendingDelivery = nil
        retryTimer?.invalidate()
        retryTimer = nil
        logLoopDecision(
            category: "delivery",
            decision: "inject_now",
            detail: "attempt=\(delivery.attemptCount)",
            metadata: ["run_id": runID, "agent_id": agentID]
        )
        injectPayload(payload, runID: runID, agentID: agentID)
    }

    private func scheduleRetry() {
        guard let delivery = pendingDelivery else { return }
        let exponential = Self.retryBaseInterval * pow(2.0, Double(max(0, delivery.attemptCount - 1)))
        let delay = min(Self.retryMaxInterval, exponential)
        logDebugEvent(.retryScheduled, detail: "attempt \(delivery.attemptCount), next in \(delay)s")
        logLoopDecision(
            category: "delivery_retry",
            decision: "scheduled",
            detail: "attempt=\(delivery.attemptCount) delay=\(delay)",
            metadata: ["run_id": delivery.runID, "agent_id": delivery.agentID]
        )
        emitStatus(runID: delivery.runID, agentID: delivery.agentID, status: .queued, phaseText: "retry attempt \(delivery.attemptCount) in \(Int(delay))s")

        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.attemptDelivery()
            }
        }
    }

    // MARK: - Payload Construction

    private func buildPayload(newMessages: [GroupMessage]) -> String {
        let labels = sessionManager.map { groupSession.participantDisplayNames(sessionManager: $0) } ?? [:]
        let myName = labels[sessionID] ?? cliSession?.target.name ?? "AI"
        let otherNames = groupSession.participantSessionIDs
            .filter { $0 != sessionID }
            .map { labels[$0] ?? "AI" }
        let historyPath = historyStore.historyFilePath(for: groupSession)

        return GroupChatPromptConfig.shared.render(
            myName: myName,
            participants: otherNames.joined(separator: ", "),
            historyPath: historyPath,
            newMessageCount: newMessages.count
        )
    }

    // MARK: - Inject & Capture

    private func injectPayload(_ payload: String, runID: String, agentID: String) {
        guard let termView = TerminalViewCache.shared.terminalView(for: sessionID) else {
            // Re-enqueue for retry if not already pending (direct call from legacy path).
            if pendingDelivery == nil {
                enqueueDelivery(payload: payload, runID: runID, agentID: agentID, relevantMessages: [])
            }
            return
        }
        let coordinator = TerminalViewCache.shared.coordinator(for: sessionID)
        let token = UUID()
        let startRow = termView.currentScrollInvariantRow()

        lastSeenSequence = groupSession.sequence
        isProcessing = true
        lastLoggedRawOutput = ""
        logLoopDecision(
            category: "inject",
            decision: "start",
            detail: "payload=\(payload.count)chars row=\(startRow)",
            metadata: ["run_id": runID, "agent_id": agentID]
        )
        emitStatus(runID: runID, agentID: agentID, status: .running, phaseText: "injecting prompt")
        emitEphemeralMessage(runID: runID, agentID: agentID, kind: .action, text: "Prompt injected into terminal")
        activeTurn = TurnContext(
            token: token,
            turnID: UUID(),
            runID: runID,
            agentID: agentID,
            injectedAtSequence: lastSeenSequence,
            payload: payload,
            injectionStartRow: startRow
        )

        // Prepare the coordinator: flush pending turn, create a single user block,
        // and reset output tracking so per-line commits don't happen.
        coordinator?.prepareForProgrammaticInput(payload)

        // Suppress input tracking so that send(source:data:) doesn't create
        // per-line user blocks via commitInputLine.
        termView.suppressInputTracking = true
        termView.sendAsPaste(payload)

        // Small delay to let the terminal process the bracketed paste before sending Enter.
        // This fixes the issue where gemini shows "[Pasted Text: N lines]" without executing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard self.activeTurn?.token == token else { return }
            termView.send(txt: "\r")
            termView.suppressInputTracking = false

            // Record where to start reading the response buffer.
            self.activeTurn?.injectionStartRow = termView.currentScrollInvariantRow()
            self.emitStatus(runID: runID, agentID: agentID, status: .thinking, phaseText: "waiting for model output")
            self.logLoopDecision(
                category: "inject",
                decision: "submitted",
                detail: "enter_sent row=\(self.activeTurn?.injectionStartRow ?? -1)",
                metadata: ["run_id": runID, "agent_id": agentID]
            )
            self.refreshDebugStatus(inputLoop: .idle, outputLoop: .polling)
        }
    }

    private func captureAndPost() {
        guard let session = cliSession,
              let termView = TerminalViewCache.shared.terminalView(for: sessionID),
              let turn = activeTurn else {
            if let turn = activeTurn {
                logLoopDecision(
                    category: "output_capture",
                    decision: "lost_handle",
                    detail: "requeue_payload",
                    metadata: ["run_id": turn.runID, "agent_id": turn.agentID]
                )
                emitStatus(runID: turn.runID, agentID: turn.agentID, status: .error, phaseText: "lost terminal/session handle")
                // Re-enqueue the payload for retry instead of silently dropping.
                let payload = turn.payload
                let runID = turn.runID
                let agentID = turn.agentID
                clearActiveTurn(resetProcessing: true)
                enqueueDelivery(payload: payload, runID: runID, agentID: agentID, relevantMessages: [])
                return
            }
            isProcessing = false
            logLoopDecision(category: "output_capture", decision: "skip", detail: "no_active_turn")
            refreshDebugStatus(outputLoop: .idle)
            return
        }

        refreshDebugStatus(outputLoop: .capturing)
        emitStatus(runID: turn.runID, agentID: turn.agentID, status: .toolRunning, phaseText: "capturing terminal output")

        // Read the terminal buffer from where injection output started.
        let rawOutput = termView.getBufferText(fromRow: turn.injectionStartRow, excludePromptLine: true)
        logLoopDecision(
            category: "output_capture",
            decision: "read_buffer",
            detail: "raw_chars=\(rawOutput.count) row=\(turn.injectionStartRow)",
            metadata: ["run_id": turn.runID, "agent_id": turn.agentID]
        )
        logBackendOutputDelta(rawOutput, runID: turn.runID, agentID: turn.agentID)

        guard let content = Self.cleanGroupChatResponse(rawOutput, payload: turn.payload) else {
            // Empty content — do nothing; the next poll cycle will retry.
            logLoopDecision(
                category: "output_capture",
                decision: "cleaned_empty",
                detail: "wait_next_poll",
                metadata: ["run_id": turn.runID, "agent_id": turn.agentID]
            )
            refreshDebugStatus(outputLoop: .polling)
            return
        }

        emitStatus(runID: turn.runID, agentID: turn.agentID, status: .summarizing, phaseText: "finalizing response")
        emitEphemeralMessage(
            runID: turn.runID,
            agentID: turn.agentID,
            kind: .result,
            text: String(content.prefix(200))
        )

        // Save turn info before clearing — we need runID/agentID for folding.
        let savedRunID = turn.runID
        let savedAgentID = turn.agentID
        let savedTurnID = turn.turnID

        clearActiveTurn(resetProcessing: true)

        // PASS protocol: AI has nothing to add — skip posting and don't notify others.
        if Self.isPassResponse(content) {
            consecutivePassCount += 1
            debugStatus.consecutivePassCount = consecutivePassCount
            logDebugEvent(.passDetected, detail: "consecutive #\(consecutivePassCount)")
            logLoopDecision(
                category: "output_capture",
                decision: "pass_detected",
                detail: "consecutive=\(consecutivePassCount)",
                metadata: ["run_id": savedRunID, "agent_id": savedAgentID]
            )
            onPassStateChanged?(sessionID, true)
            emitStatus(runID: savedRunID, agentID: savedAgentID, status: .done, phaseText: "PASS")
            // Remove the ephemeral run for PASS responses too.
            groupSession.removeEphemeralRun(id: "\(savedRunID)::\(savedAgentID)")
            refreshDebugStatus(outputLoop: .idle)
            // Don't blindly advance lastSeenSequence — messages from users or
            // other AIs may have arrived while we were processing. Let the
            // next checkForNewMessages() pick them up.
            checkForNewMessages()
            return
        }

        // Real response — reset consecutive PASS count
        consecutivePassCount = 0
        debugStatus.consecutivePassCount = 0
        onPassStateChanged?(sessionID, false)
        logDebugEvent(.outputCaptured, detail: "\(content.prefix(80))...")
        logLoopDecision(
            category: "output_capture",
            decision: "post_message",
            detail: "content_chars=\(content.count)",
            metadata: ["run_id": savedRunID, "agent_id": savedAgentID]
        )

        // Post the response back to the group
        let labels = sessionManager.map { groupSession.participantDisplayNames(sessionManager: $0) } ?? [:]

        // Fold ephemeral run cards into the message as thinkingProcess.
        let runKey = "\(savedRunID)::\(savedAgentID)"
        let thinkingCards: [GroupMessage.ThinkingCard]? = groupSession.ephemeralRunCards(
            runId: savedRunID, agentId: savedAgentID
        )?.map { card in
            GroupMessage.ThinkingCard(kind: card.kind.rawValue, text: card.text, ts: card.ts)
        }

        let aiMessage = GroupMessage(
            source: .ai(
                name: labels[sessionID] ?? session.target.name,
                sessionID: sessionID,
                colorHex: session.target.colorHex
            ),
            content: content,
            thinkingProcess: thinkingCards
        )
        guard postedTurnIDs.insert(savedTurnID).inserted else { return }
        let fingerprint = "\(sessionID.uuidString):\(savedTurnID.uuidString):\(Self.dedupeKey(for: content))"
        guard postedFingerprints.insert(fingerprint).inserted else { return }
        groupSession.appendMessage(aiMessage)
        groupSession.applyRealtimeEvent(
            .assistantMessage(
                GroupChatAssistantMessageEvent(
                    eventId: Self.nextEventID(),
                    runId: savedRunID,
                    agentId: savedAgentID,
                    messageId: aiMessage.id.uuidString,
                    content: content,
                    ts: Date(),
                    ephemeral: false,
                    persist: true
                )
            )
        )
        // Remove the ephemeral run now that it's folded into the message.
        groupSession.removeEphemeralRun(id: runKey)
        emitStatus(runID: savedRunID, agentID: savedAgentID, status: .done)

        // Persist history
        historyStore.save(groupSession)
        logLoopDecision(
            category: "output_capture",
            decision: "persisted",
            detail: "history_saved",
            metadata: ["run_id": savedRunID, "agent_id": savedAgentID]
        )

        refreshDebugStatus(outputLoop: .idle)

        // Don't blindly advance lastSeenSequence to groupSession.sequence here.
        // Messages from users or other AIs may have arrived while we were
        // processing. Instead, immediately check for new messages — the filter
        // in checkForNewMessages() will skip our own response (same sessionID),
        // and any messages from others will be properly picked up.
        checkForNewMessages()
        drainPendingFanoutIfReady(forceStableIdle: false)
    }

    private func clearActiveTurn(resetProcessing: Bool) {
        activeTurn = nil
        if resetProcessing {
            isProcessing = false
        }
    }

    private func drainPendingFanoutIfReady(forceStableIdle: Bool) {
        guard let pending = pendingFanoutSequence else { return }
        guard !isProcessing else { return }
        if forceStableIdle && !isStableIdle {
            return
        }
        if !forceStableIdle, !(cliSession?.state == .waitingForInput || isStableIdle) {
            return
        }
        pendingFanoutSequence = nil
        logLoopDecision(
            category: "fanout_delivery",
            decision: "drain",
            detail: "pending_seq=\(pending) seen=\(lastSeenSequence) current=\(groupSession.sequence)"
        )
        checkForNewMessages()
    }

    // MARK: - Response Cleaning

    /// Cleans raw terminal buffer output for group chat posting.
    /// Removes echoed payload lines, system instructions, and TUI chrome.
    static func cleanGroupChatResponse(_ text: String, payload: String) -> String? {
        guard !text.isEmpty else { return nil }

        let rawLines = sanitizeControlCharacters(in: text).components(separatedBy: .newlines)

        // Early exit: if the last meaningful line is [PASS], the AI has nothing
        // to add. Everything before it (thinking, tool-use chrome, narration)
        // is just process output — discard it all.
        if let lastMeaningful = rawLines.lazy
            .map({ normalizedPromptLine($0) })
            .last(where: { !$0.isEmpty }),
           isPassResponse(lastMeaningful) {
            return "[PASS]"
        }
        // Only do range-based block stripping when this looks like an echoed injected payload.
        let payloadLines = Set(
            sanitizeControlCharacters(in: payload)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let normalizedLines = removeInjectedPromptBlock(from: rawLines, payloadLines: payloadLines)
        
        // Signatures of lines we injected and want to hide if echoed
        let promptSignatures = [
            "[Group Chat] You are \"",
            "Full history: ",
            "History: ",
            "participants: ",
            "Please review the chat history and decide",
            "nothing to say or do, reply with exactly",
            "reply with exactly \"[PASS]\"",
            "New messages since your last response:",
            "Reply if you have something meaningful to contribute.",
            "If you have nothing to add, reply with exactly",
            "# AGENTS.md instructions",
            "<environment_context>",
            "</environment_context>",
            "<collaboration_mode>",
            "</collaboration_mode>"
        ]

        // Prepare payload lines for exact match filtering
        var filtered: [String] = []
        var insideCodeFence = false
        var insideSystemBlock = false

        for line in normalizedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let normalizedTrimmed = normalizedPromptLine(trimmed)
            
            // 1. Handle code fences - preserve everything inside them
            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                filtered.append(line)
                continue
            }
            
            if insideCodeFence {
                filtered.append(line)
                continue
            }

            // 2. Block-level system filtering
            if trimmed.hasPrefix("<environment_context>") || 
               trimmed.hasPrefix("<collaboration_mode>") ||
               trimmed.hasPrefix("# AGENTS.md") {
                insideSystemBlock = true
                continue
            }
            
            if trimmed.hasPrefix("</environment_context>") || 
               trimmed.hasPrefix("</collaboration_mode>") {
                insideSystemBlock = false
                continue
            }
            
            if insideSystemBlock {
                continue
            }

            // --- Outside Special Blocks Filtering ---

            // 3. Skip TUI Chrome (borders, etc.)
            if isTUIChromeLine(line) { continue }

            // 3b. Skip status/spinner lines (e.g. "Working(0s • esc to interrupt)")
            if Self.isStatusLine(line) { continue }

            // 4. Skip Prompt Signatures (prefix match)
            if promptSignatures.contains(where: { normalizedTrimmed.hasPrefix($0) }) {
                continue
            }

            // 4b. Skip terminal-wrapped instruction fragments (contains match).
            // The instruction can wrap at arbitrary points; catch fragments
            // that don't start at a known prefix.
            if isWrappedInstructionFragment(normalizedTrimmed) {
                continue
            }
            
            // 5. Skip Exact Payload Echoes
            if payloadLines.contains(trimmed) {
                continue
            }
            
            // 6. Skip role metadata echo [You]: ... or [Name]: ...
            if (trimmed.hasPrefix("[You]:") || trimmed.hasPrefix("[") && trimmed.contains("]:")) && 
               payloadLines.contains(where: { $0.contains(trimmed) }) {
                continue
            }
            
            filtered.append(line)
        }

        // Trim leading/trailing blank lines from the result
        while filtered.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            filtered.removeFirst()
        }
        while filtered.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            filtered.removeLast()
        }

        let cleaned = filtered.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            noteMetric("empty_after_clean")
            return nil
        }
        if isPassResponse(cleaned) {
            noteMetric("pass_detected")
        }
        return cleaned
    }

    private static func removeInjectedPromptBlock(from lines: [String], payloadLines: Set<String>) -> [String] {
        let headContainsSignals = lines.prefix(20).contains { line in
            let normalized = normalizedPromptLine(line)
            return normalized.hasPrefix("[Group Chat] You are")
                || normalized.hasPrefix("Full history:")
                || normalized.contains("participants:")
        }
        guard headContainsSignals else { return lines }

        // Find the start of the injected prompt block.
        guard let start = lines.firstIndex(where: {
            let norm = normalizedPromptLine($0)
            return norm.hasPrefix("[Group Chat] You are")
                || norm.hasPrefix("New messages since your last response:")
        }) else {
            return lines
        }

        // Find the end: last line that looks like part of the injected payload.
        let endMarkerChecks: [(String) -> Bool] = [
            { $0.contains("[PASS]") },
            { $0.contains("nothing to say or do") },
            { $0.hasPrefix("Please review the chat history") },
            { $0.hasPrefix("Reply if you have something meaningful") },
        ]
        var end = start
        for check in endMarkerChecks {
            if let idx = lines[start...].lastIndex(where: { check(normalizedPromptLine($0)) }) {
                end = max(end, idx)
                break
            }
        }

        // Sanity: don't remove too large a range.
        guard end - start <= 400 else {
            return removeLines(at: [start], from: lines)
        }

        var result = lines
        result.removeSubrange(start...end)
        return result
    }

    private static func removeLines(at indices: [Int], from lines: [String]) -> [String] {
        let indexSet = Set(indices.filter { $0 >= 0 && $0 < lines.count })
        guard !indexSet.isEmpty else { return lines }
        return lines.enumerated().compactMap { idx, line in
            indexSet.contains(idx) ? nil : line
        }
    }

    private static func normalizedPromptLine(_ line: String) -> String {
        var out = line.trimmingCharacters(in: .whitespaces)
        while let first = out.first, first == ">" || first == "›" || first == "•" {
            out.removeFirst()
            out = out.trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Returns true if the line looks like a terminal-wrapped fragment of the
    /// injected group-chat instruction (not the AI's actual response).
    private static func isWrappedInstructionFragment(_ line: String) -> Bool {
        let markers = [
            "reply with exactly \"[PASS]\"",
            "nothing to say or do, reply",
            "review the chat history and decide",
        ]
        return markers.contains(where: { line.contains($0) })
    }

    private static func noteMetric(_ name: String) {
        print("[GroupChatMetric] \(name)=1")
    }

    private static func dedupeKey(for content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// Returns true if the line consists entirely of TUI chrome characters
    /// (box-drawing, block elements) and spaces.
    private static func isTUIChromeLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let tuiChars = CharacterSet(charactersIn: "▄▀█▌▐░▒▓─│┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬ ")
        return line.unicodeScalars.allSatisfy { tuiChars.contains($0) }
    }

    /// Returns true if the line is a CLI tool status/spinner indicator
    /// (e.g. "•Working(0s • esc to interrupt)", "Thinking...", spinner chars).
    /// These appear while the AI is still processing and should not be captured as content.
    private static func isStatusLine(_ line: String) -> Bool {
        let trimmed = normalizedPromptLine(line)
        guard !trimmed.isEmpty else { return false }

        // Claude Code / similar: "Working(Ns", "Working(Nm"
        if trimmed.contains("Working(") && trimmed.contains("s") { return true }
        // "esc to interrupt" / "esc to cancel"
        if trimmed.contains("esc to interrupt") || trimmed.contains("esc to cancel") { return true }
        // Standalone thinking indicators
        if trimmed == "Thinking..." || trimmed == "Thinking…" { return true }
        // Spinner characters only (braille spinners, etc.)
        let spinnerChars = CharacterSet(charactersIn: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏✦⣾⣽⣻⢿⡿⣟⣯⣷ ")
        if trimmed.unicodeScalars.allSatisfy({ spinnerChars.contains($0) }) { return true }

        return false
    }
    /// Drops non-printable control characters (for example NUL) so rendering is stable.
    private static func sanitizeControlCharacters(in text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                if scalar.value == 9 || scalar.value == 10 || scalar.value == 13 {
                    scalars.append(scalar)
                }
                continue
            }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Returns true if the cleaned response is a PASS signal (AI has nothing to add).
    /// Checks only the LAST non-empty line, so a response that merely *discusses*
    /// [PASS] (e.g. "implement the [PASS] UI") is not treated as a skip.
    static func isPassResponse(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let keyword = GroupChatPromptConfig.shared.passKeyword
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Also match without brackets, e.g. "[PASS]" -> "pass"
        let bare = keyword.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        let lower = trimmed.lowercased()
        if lower == keyword || lower == bare { return true }

        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let lastLine = lines.last(where: { !$0.isEmpty }) else { return false }
        let lastLower = lastLine.lowercased()
        return lastLower == keyword || lastLower == bare
            || lastLower.hasSuffix(keyword) || lastLower.hasSuffix(bare + "]")
    }

    // MARK: - User Control

    /// Resets the controller for a new conversation round initiated by the user.
    /// Re-establishes observation so polling continues to work.
    func reset() {
        logLoopDecision(category: "lifecycle", decision: "reset", detail: "controller reset")
        lastSeenSequence = groupSession.sequence
        clearActiveTurn(resetProcessing: true)
        waitingForInputSince = nil
        pendingDelivery = nil
        retryTimer?.invalidate()
        retryTimer = nil
        lastLoggedRawOutput = ""
        postedTurnIDs.removeAll()
        postedFingerprints.removeAll()
        outputPollTimer?.invalidate()
        outputPollTimer = nil
        inputPollTimer?.invalidate()
        inputPollTimer = nil
        cancellables.removeAll()

        // Restart observation so the controller doesn't become permanently deaf.
        startObserving()
    }

    /// Stops current processing only, while keeping polling alive.
    func stop() {
        logLoopDecision(category: "lifecycle", decision: "stop", detail: "stop processing keep polling")
        clearActiveTurn(resetProcessing: true)
        waitingForInputSince = nil
        pendingDelivery = nil
        retryTimer?.invalidate()
        retryTimer = nil
        lastLoggedRawOutput = ""
        refreshDebugStatus(inputLoop: .idle, outputLoop: .idle)
    }

    /// Stops all observation and polling. This should only be used when closing the group chat.
    func shutdown() {
        logLoopDecision(category: "lifecycle", decision: "shutdown", detail: "stop polling and observing")
        clearActiveTurn(resetProcessing: true)
        waitingForInputSince = nil
        pendingDelivery = nil
        retryTimer?.invalidate()
        retryTimer = nil
        lastLoggedRawOutput = ""
        outputPollTimer?.invalidate()
        outputPollTimer = nil
        inputPollTimer?.invalidate()
        inputPollTimer = nil
        cancellables.removeAll()
        refreshDebugStatus(inputLoop: .stopped, outputLoop: .stopped)
    }

    deinit {
        shutdown()
    }
}
