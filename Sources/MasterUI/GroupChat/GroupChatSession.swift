import Foundation
import Combine

enum GroupChatTab {
    case conversation
    case history
    case settings
    case debug
}

enum GroupChatAgentStatus: String, CaseIterable {
    case idle
    case queued
    case running
    case thinking
    case callingTool = "calling_tool"
    case waitingTool = "waiting_tool"
    case toolRunning = "tool_running"
    case drafting
    case streaming
    case summarizing
    case done
    case error

    var rank: Int {
        switch self {
        case .idle: return 0
        case .queued: return 1
        case .running: return 2
        case .thinking: return 3
        case .callingTool, .toolRunning: return 4
        case .waitingTool: return 5
        case .drafting: return 6
        case .streaming: return 7
        case .summarizing: return 8
        case .done, .error: return 9
        }
    }

    var isTerminal: Bool {
        self == .done || self == .error
    }
}

enum GroupChatEphemeralKind: String {
    case thought
    case action
    case result
}

struct GroupChatAgentStatusEvent {
    let eventId: String
    let runId: String
    let agentId: String
    let status: GroupChatAgentStatus
    let phaseText: String?
    let ts: Date
    let ephemeral: Bool
    let persist: Bool
}

struct GroupChatEphemeralMessageEvent {
    let eventId: String
    let runId: String
    let agentId: String
    let kind: GroupChatEphemeralKind
    let text: String
    let meta: [String: String]
    let ts: Date
    let ephemeral: Bool
    let persist: Bool
}

struct GroupChatAssistantMessageEvent {
    let eventId: String
    let runId: String
    let agentId: String
    let messageId: String
    let content: String
    let ts: Date
    let ephemeral: Bool
    let persist: Bool
}

enum GroupChatRealtimeEvent {
    case agentStatus(GroupChatAgentStatusEvent)
    case ephemeralMessage(GroupChatEphemeralMessageEvent)
    case assistantMessage(GroupChatAssistantMessageEvent)

    var eventId: String {
        switch self {
        case .agentStatus(let event):
            return event.eventId
        case .ephemeralMessage(let event):
            return event.eventId
        case .assistantMessage(let event):
            return event.eventId
        }
    }
}

struct GroupChatAgentStateSnapshot: Identifiable {
    var id: String { agentId }
    let runId: String
    let agentId: String
    let status: GroupChatAgentStatus
    let phaseText: String?
    let ts: Date
}

struct GroupChatEphemeralCard: Identifiable {
    let id: String
    let runId: String
    let agentId: String
    let kind: GroupChatEphemeralKind
    let text: String
    let ts: Date
}

struct GroupChatEphemeralRun: Identifiable {
    var id: String { "\(runId)::\(agentId)" }
    let runId: String
    let agentId: String
    var cards: [GroupChatEphemeralCard]
    var lastUpdatedAt: Date
    var completedAt: Date?
    var isCollapsed: Bool
}

// MARK: - GroupChatSession

/// Represents a single group chat where multiple CLI sessions participate.
class GroupChatSession: ObservableObject, Identifiable {
    private struct RunAgentKey: Hashable {
        let runId: String
        let agentId: String
    }

    let id: UUID
    let createdAt: Date

    @Published var title: String
    @Published var participantSessionIDs: [UUID]
    @Published var messages: [GroupMessage]
    @Published var lastActivityDate: Date
    @Published var hasUnreadActivity: Bool = false
    @Published var activeTab: GroupChatTab = .conversation

    /// Message sequence number, incremented on each append.
    @Published var sequence: Int = 0

    /// Live in-memory state for agent status badges keyed by agent identifier.
    @Published private(set) var liveAgentStates: [String: GroupChatAgentStateSnapshot] = [:]

    /// Live in-memory ephemeral cards grouped by run/agent. Never persisted.
    @Published private(set) var ephemeralRuns: [GroupChatEphemeralRun] = []

    /// Sequence for non-persistent live updates so the UI can scroll/react.
    @Published private(set) var liveSequence: Int = 0

    /// Event fired after each message append so subscribers can react immediately.
    struct MessageEvent {
        let message: GroupMessage
        let sequence: Int
    }

    let messagePublisher = PassthroughSubject<MessageEvent, Never>()
    let realtimeEventPublisher = PassthroughSubject<GroupChatRealtimeEvent, Never>()
    private var seenLiveEventIDs = Set<String>()
    private var fallbackRunIDByAgentID: [String: String] = [:]
    private var statusByRunAgent: [RunAgentKey: GroupChatAgentStatus] = [:]

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
        self.lastActivityDate = createdAt
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
        lastActivityDate = Date()
        hasUnreadActivity = true
        messagePublisher.send(MessageEvent(message: message, sequence: sequence))
    }

    func applyRealtimeEvent(_ event: GroupChatRealtimeEvent) {
        guard seenLiveEventIDs.insert(event.eventId).inserted else { return }

        switch event {
        case .agentStatus(let statusEvent):
            guard statusEvent.ephemeral, !statusEvent.persist else { return }
            let runId = resolvedRunID(for: statusEvent.agentId, explicitRunID: statusEvent.runId, at: statusEvent.ts)
            guard shouldAdvanceStatus(runId: runId, agentId: statusEvent.agentId, next: statusEvent.status) else { return }
            let next = GroupChatAgentStateSnapshot(
                runId: runId,
                agentId: statusEvent.agentId,
                status: statusEvent.status,
                phaseText: statusEvent.phaseText,
                ts: statusEvent.ts
            )
            liveAgentStates[statusEvent.agentId] = next
            if statusEvent.status.isTerminal {
                markRunCompleted(runId: runId, agentId: statusEvent.agentId, at: statusEvent.ts)
            }
            liveSequence += 1

        case .ephemeralMessage(let messageEvent):
            guard messageEvent.ephemeral, !messageEvent.persist else { return }
            let runId = resolvedRunID(for: messageEvent.agentId, explicitRunID: messageEvent.runId, at: messageEvent.ts)
            let card = GroupChatEphemeralCard(
                id: messageEvent.eventId,
                runId: runId,
                agentId: messageEvent.agentId,
                kind: messageEvent.kind,
                text: messageEvent.text,
                ts: messageEvent.ts
            )
            appendEphemeralCard(card, forRunID: runId, agentId: messageEvent.agentId, ts: messageEvent.ts)
            liveSequence += 1

        case .assistantMessage(let messageEvent):
            guard !messageEvent.ephemeral, messageEvent.persist else { return }
            _ = shouldAdvanceStatus(runId: messageEvent.runId, agentId: messageEvent.agentId, next: .done)
            markRunCompleted(runId: messageEvent.runId, agentId: messageEvent.agentId, at: messageEvent.ts)
            liveSequence += 1
        }

        realtimeEventPublisher.send(event)
    }

    private func appendEphemeralCard(
        _ card: GroupChatEphemeralCard,
        forRunID runId: String,
        agentId: String,
        ts: Date
    ) {
        let runKey = "\(runId)::\(agentId)"
        if let index = ephemeralRuns.firstIndex(where: { $0.id == runKey }) {
            guard !ephemeralRuns[index].cards.contains(where: { $0.id == card.id }) else { return }
            ephemeralRuns[index].cards.append(card)
            ephemeralRuns[index].cards.sort { $0.ts < $1.ts }
            ephemeralRuns[index].lastUpdatedAt = ts
            if ephemeralRuns[index].completedAt == nil {
                ephemeralRuns[index].isCollapsed = false
            }
        } else {
            ephemeralRuns.append(
                GroupChatEphemeralRun(
                    runId: runId,
                    agentId: agentId,
                    cards: [card],
                    lastUpdatedAt: ts,
                    completedAt: nil,
                    isCollapsed: false
                )
            )
        }
        ephemeralRuns.sort { $0.lastUpdatedAt < $1.lastUpdatedAt }
        if ephemeralRuns.count > 50 {
            ephemeralRuns.removeFirst(ephemeralRuns.count - 50)
        }
    }

    private func markRunCompleted(runId: String, agentId: String, at ts: Date) {
        let runKey = "\(runId)::\(agentId)"
        guard let index = ephemeralRuns.firstIndex(where: { $0.id == runKey }) else { return }
        if ephemeralRuns[index].completedAt == nil {
            ephemeralRuns[index].completedAt = ts
        }
        ephemeralRuns[index].isCollapsed = true
        ephemeralRuns[index].lastUpdatedAt = max(ephemeralRuns[index].lastUpdatedAt, ts)
    }

    private func resolvedRunID(for agentId: String, explicitRunID: String, at ts: Date) -> String {
        if !explicitRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fallbackRunIDByAgentID[agentId] = explicitRunID
            return explicitRunID
        }
        if let fallback = fallbackRunIDByAgentID[agentId] {
            return fallback
        }
        let fallback = "fallback-\(agentId)-\(Int(ts.timeIntervalSince1970 * 1000))"
        fallbackRunIDByAgentID[agentId] = fallback
        return fallback
    }

    private func shouldAdvanceStatus(runId: String, agentId: String, next: GroupChatAgentStatus) -> Bool {
        let key = RunAgentKey(runId: runId, agentId: agentId)
        guard let current = statusByRunAgent[key] else {
            statusByRunAgent[key] = next
            return true
        }

        if current.isTerminal {
            return false
        }
        if next.rank < current.rank {
            return false
        }
        if next.rank == current.rank {
            return false
        }

        statusByRunAgent[key] = next
        return true
    }

    /// Returns the ephemeral cards for a given run/agent pair, if any.
    func ephemeralRunCards(runId: String, agentId: String) -> [GroupChatEphemeralCard]? {
        let runKey = "\(runId)::\(agentId)"
        return ephemeralRuns.first(where: { $0.id == runKey })?.cards
    }

    /// Removes an ephemeral run by its composite id (runId::agentId).
    func removeEphemeralRun(id: String) {
        ephemeralRuns.removeAll { $0.id == id }
        liveSequence += 1
    }

    /// Returns all messages after the given sequence number.
    func messages(after afterSequence: Int) -> [GroupMessage] {
        let startIndex = afterSequence
        guard startIndex < messages.count else { return [] }
        return Array(messages[startIndex...])
    }

    /// Returns participant display names and disambiguates duplicate names with a stable alias.
    /// Example: "Codex@codex-1a2b3c"
    func participantDisplayNames(sessionManager: CLISessionManager) -> [UUID: String] {
        var baseNames: [UUID: String] = [:]
        for sessionID in participantSessionIDs {
            if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                baseNames[sessionID] = session.target.name
                continue
            }
            if let historical = messages.last(where: {
                if case .ai(_, let sid, _) = $0.source {
                    return sid == sessionID
                }
                return false
            }), case .ai(let name, _, _) = historical.source {
                baseNames[sessionID] = name
            }
        }

        let counts = Dictionary(grouping: baseNames.values, by: { $0 }).mapValues(\.count)
        var labels: [UUID: String] = [:]

        for sessionID in participantSessionIDs {
            let base = baseNames[sessionID] ?? "AI"
            if (counts[base] ?? 0) <= 1 {
                labels[sessionID] = base
                continue
            }
            let sourceTag: String
            if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                sourceTag = Self.sourceTag(for: session.target)
            } else {
                sourceTag = "cli"
            }
            labels[sessionID] = "\(base)@\(sourceTag)-\(Self.shortID(sessionID))"
        }

        return labels
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }

    private static func sourceTag(for target: AITarget) -> String {
        let raw = URL(fileURLWithPath: target.executablePath).lastPathComponent
        let fallback = target.name.lowercased()
        let candidate = raw.isEmpty ? fallback : raw.lowercased()
        let sanitized = candidate.map { scalar -> Character in
            if scalar.isLetter || scalar.isNumber {
                return scalar
            }
            return "-"
        }
        let compact = String(sanitized)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? "cli" : compact
    }
}
