import SwiftUI
import AppKit

// MARK: - GroupChatConversationView

/// Displays the unified conversation view for a group chat.
struct GroupChatConversationView: View {
    @ObservedObject var chat: GroupChatSession
    @ObservedObject var coordinator: GroupChatCoordinator
    @ObservedObject var sessionManager: CLISessionManager
    @State private var showDebugPanel = false

    /// Active ephemeral runs: only the latest incomplete run per agent.
    private var activeRuns: [GroupChatEphemeralRun] {
        var latestByAgent: [String: GroupChatEphemeralRun] = [:]
        for run in chat.ephemeralRuns where run.completedAt == nil {
            latestByAgent[run.agentId] = run
        }
        return Array(latestByAgent.values).sorted { $0.lastUpdatedAt < $1.lastUpdatedAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Member sidebar
            GroupChatMemberSidebar(
                chat: chat,
                coordinator: coordinator,
                sessionManager: sessionManager,
                participantLabels: participantLabels,
                statusDisplay: { statusDisplay(for: $0) },
                statusColor: { statusColor(for: $0) }
            )

            Divider()

            // Main conversation area
            VStack(spacing: 0) {
                // Header
                conversationHeader
                    .background(.ultraThinMaterial)

                Divider()

                // Debug panel
                if showDebugPanel {
                    ParticipantDebugPanel(
                        coordinator: coordinator,
                        sessionManager: sessionManager
                    )
                    Divider()
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(chat.messages) { message in
                                GroupMessageBubble(
                                    message: message,
                                    participantLabels: participantLabels
                                )
                                .id("msg-\(message.id.uuidString)")
                            }

                            ForEach(activeRuns) { run in
                                EphemeralRunCard(
                                    run: run,
                                    displayName: displayName(forAgentID: run.agentId),
                                    colorHex: colorHex(forAgentID: run.agentId)
                                )
                                .id("run-\(run.id)")
                            }

                            // Stall banner
                            if coordinator.isStalled {
                                stalledBanner
                            }

                            // Active processing indicator
                            if coordinator.isConversationActive {
                                pendingIndicator
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: chat.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: chat.liveSequence) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                // Input — always enabled
                GroupChatInputBar(
                    coordinator: coordinator,
                    isWaiting: false
                )
                .background(.regularMaterial)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastRunID = activeRuns.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("run-\(lastRunID)", anchor: .bottom)
            }
            return
        }
        if let lastMessageID = chat.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("msg-\(lastMessageID.uuidString)", anchor: .bottom)
            }
        }
    }

    // MARK: - Header

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            Text(chat.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Stall badge
            if coordinator.isStalled {
                Text("Stalled")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange, in: Capsule())
                    .help("All AIs passed — conversation stalled")
                    .transition(.opacity.combined(with: .scale))
            }

            // Stop button when conversation is active
            if coordinator.isConversationActive {
                Button(action: { coordinator.stopAll() }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.8), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Stop all AI responses")
                .transition(.opacity.combined(with: .scale))
            }

            // Debug toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDebugPanel.toggle()
                }
            } label: {
                Image(systemName: showDebugPanel ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 12))
                    .foregroundStyle(showDebugPanel ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle debug panel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Stalled Banner

    private var stalledBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text("Conversation stalled — all AIs passed. Send a message to continue.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
    }

    // MARK: - Pending Indicator

    private var pendingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(pendingNames)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: Capsule())
        .padding(.top, 4)
    }

    private var pendingNames: String {
        let names = coordinator.controllers
            .compactMap { sessionID, controller -> String? in
                guard controller.isProcessing else { return nil }
                return participantLabels[sessionID] ?? controller.cliSession?.target.name
            }
            .filter { !$0.isEmpty }
        if names.isEmpty { return "Thinking..." }
        return names.joined(separator: ", ") + " typing..."
    }

    private var participantLabels: [UUID: String] {
        chat.participantDisplayNames(sessionManager: sessionManager)
    }

    private func colorHex(for sessionID: UUID) -> String {
        sessionManager.sessions.first(where: { $0.id == sessionID })?.target.colorHex ?? "#9CA3AF"
    }

    private func colorHex(forAgentID agentId: String) -> String {
        if let resolved = resolveSessionID(forAgentID: agentId) {
            return colorHex(for: resolved)
        }
        return "#9CA3AF"
    }

    private func displayName(forAgentID agentId: String) -> String {
        if let resolved = resolveSessionID(forAgentID: agentId) {
            return participantLabels[resolved] ?? agentId
        }
        return agentId
    }

    private func resolveSessionID(forAgentID agentId: String) -> UUID? {
        if let uuid = UUID(uuidString: agentId), chat.participantSessionIDs.contains(uuid) {
            return uuid
        }

        let normalizedAgentID = agentId.lowercased()
        for sessionID in chat.participantSessionIDs {
            let label = (participantLabels[sessionID] ?? "").lowercased()
            let targetName = (sessionManager.sessions.first(where: { $0.id == sessionID })?.target.name ?? "").lowercased()
            if normalizedAgentID == label
                || normalizedAgentID == targetName
                || label.contains(normalizedAgentID)
                || normalizedAgentID.contains(label)
                || targetName.contains(normalizedAgentID)
                || normalizedAgentID.contains(targetName) {
                return sessionID
            }
        }
        return nil
    }

    private func statusDisplay(for sessionID: UUID) -> ParticipantStatusDisplay {
        if let status = resolvedStatus(for: sessionID) {
            let text = status.phaseText?.isEmpty == false ? status.phaseText! : localizedStatus(status.status)
            return ParticipantStatusDisplay(
                text: text,
                color: statusColor(for: status.status),
                timestamp: status.ts
            )
        }

        if let controller = coordinator.controllers[sessionID], controller.isProcessing {
            return ParticipantStatusDisplay(
                text: "streaming",
                color: statusColor(for: .streaming),
                timestamp: Date()
            )
        }

        return ParticipantStatusDisplay(
            text: "idle",
            color: statusColor(for: .idle),
            timestamp: Date()
        )
    }

    private func resolvedStatus(for sessionID: UUID) -> GroupChatAgentStateSnapshot? {
        let matching = chat.liveAgentStates.values.filter { snapshot in
            resolveSessionID(forAgentID: snapshot.agentId) == sessionID
        }
        return matching.max { $0.ts < $1.ts }
    }

    private func localizedStatus(_ status: GroupChatAgentStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .queued: return "queued"
        case .running: return "running"
        case .thinking: return "thinking"
        case .callingTool, .toolRunning: return "tool running"
        case .waitingTool: return "waiting tool"
        case .drafting: return "drafting"
        case .streaming: return "streaming"
        case .summarizing: return "summarizing"
        case .done: return "done"
        case .error: return "error"
        }
    }

    private func statusColor(for status: GroupChatAgentStatus) -> Color {
        switch status {
        case .idle:
            return .secondary
        case .queued:
            return .gray
        case .running:
            return .blue
        case .thinking:
            return .indigo
        case .callingTool, .toolRunning:
            return .orange
        case .waitingTool:
            return .yellow
        case .drafting:
            return .mint
        case .streaming:
            return .teal
        case .summarizing:
            return .purple
        case .done:
            return .green
        case .error:
            return .red
        }
    }
}

private struct ParticipantStatusDisplay {
    let text: String
    let color: Color
    let timestamp: Date
}

private struct GroupChatMemberSidebar: View {
    @ObservedObject var chat: GroupChatSession
    @ObservedObject var coordinator: GroupChatCoordinator
    @ObservedObject var sessionManager: CLISessionManager
    let participantLabels: [UUID: String]
    let statusDisplay: (UUID) -> ParticipantStatusDisplay
    let statusColor: (GroupChatAgentStatus) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Members")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(chat.participantSessionIDs, id: \.self) { sessionID in
                        if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                            let label = participantLabels[sessionID] ?? session.target.name
                            let status = statusDisplay(sessionID)
                            HStack(spacing: 8) {
                                AvatarView(name: label, colorHex: session.target.colorHex, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(status.color)
                                            .frame(width: 6, height: 6)
                                        Text(status.text)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 160)
        .background(.ultraThinMaterial)
    }
}

private struct EphemeralRunCard: View {
    let run: GroupChatEphemeralRun
    let displayName: String
    let colorHex: String

    @State private var isExpanded: Bool

    init(run: GroupChatEphemeralRun, displayName: String, colorHex: String) {
        self.run = run
        self.displayName = displayName
        self.colorHex = colorHex
        _isExpanded = State(initialValue: !run.isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(name: displayName, colorHex: colorHex, size: 20)
                Text(displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if run.completedAt != nil {
                    Text("completed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text("in progress")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(run.cards) { card in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: iconName(for: card.kind))
                                .font(.system(size: 10))
                                .foregroundStyle(iconColor(for: card.kind))
                                .frame(width: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                Text(card.ts, style: .time)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Temporary process (\(run.cards.count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .foregroundStyle(Color.secondary.opacity(0.3))
        )
        .onChange(of: run.isCollapsed) {
            if run.isCollapsed {
                isExpanded = false
            }
        }
    }

    private func iconName(for kind: GroupChatEphemeralKind) -> String {
        switch kind {
        case .thought:
            return "brain"
        case .action:
            return "wrench.and.screwdriver"
        case .result:
            return "checkmark.circle"
        }
    }

    private func iconColor(for kind: GroupChatEphemeralKind) -> Color {
        switch kind {
        case .thought:
            return .indigo
        case .action:
            return .orange
        case .result:
            return .green
        }
    }
}

// MARK: - Message Bubble

private struct GroupMessageBubble: View {
    let message: GroupMessage
    let participantLabels: [UUID: String]
    @State private var showDetails = false
    @State private var showThinking = false

    var body: some View {
        switch message.source {
        case .user:
            userBubble
        case .ai(let name, let sessionID, let colorHex):
            aiBubble(name: participantLabels[sessionID] ?? name, colorHex: colorHex)
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        let parsed = ParsedGroupMessage(message.content)
        return HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 60)
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(parsed.primaryText)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
                if let details = parsed.detailsText {
                    detailsDisclosure(details)
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }
            
            // User Avatar (Placeholder)
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
        }
    }

    private func aiBubble(name: String, colorHex: String) -> some View {
        let parsed = ParsedGroupMessage(message.content)
        return HStack(alignment: .top, spacing: 10) {
            AvatarView(name: name, colorHex: colorHex, size: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: colorHex) ?? .primary)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(parsed.primaryText)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                    .textSelection(.enabled)
                if let details = parsed.detailsText {
                    detailsDisclosure(details)
                }
                if let cards = message.thinkingProcess, !cards.isEmpty {
                    thinkingProcessDisclosure(cards)
                }
            }

            Spacer(minLength: 40)
        }
    }

    private var systemBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func detailsDisclosure(_ details: String) -> some View {
        DisclosureGroup(isExpanded: $showDetails) {
            Text(details)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
        } label: {
            Text("Show details")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thinkingProcessDisclosure(_ cards: [GroupMessage.ThinkingCard]) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: thinkingIconName(card.kind))
                            .font(.system(size: 10))
                            .foregroundStyle(thinkingIconColor(card.kind))
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Text(card.ts, style: .time)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Thinking process (\(cards.count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func thinkingIconName(_ kind: String) -> String {
        switch kind {
        case "thought": return "brain"
        case "action": return "wrench.and.screwdriver"
        case "result": return "checkmark.circle"
        default: return "circle"
        }
    }

    private func thinkingIconColor(_ kind: String) -> Color {
        switch kind {
        case "thought": return .indigo
        case "action": return .orange
        case "result": return .green
        default: return .secondary
        }
    }
}

// MARK: - Avatar View

struct AvatarView: View {
    let name: String
    let colorHex: String
    let size: CGFloat
    
    var initials: String {
        let components = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if let first = components.first?.first {
            if components.count > 1, let last = components.last?.first {
                return "\(first)\(last)".uppercased()
            }
            return String(first).uppercased()
        }
        return "?"
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: colorHex) ?? .gray)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Participant Debug Panel

/// Collapsible debug panel showing each participant's input/output loop state.
private struct ParticipantDebugPanel: View {
    @ObservedObject var coordinator: GroupChatCoordinator
    @ObservedObject var sessionManager: CLISessionManager
    @State private var showEventLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Loop Debug")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if coordinator.isStalled {
                    Text("STALLED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showEventLog.toggle()
                    }
                } label: {
                    Text(showEventLog ? "Hide Events" : "Events")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("seq: \(coordinator.groupSession.sequence)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(coordinator.groupSession.participantSessionIDs, id: \.self) { sessionID in
                if let controller = coordinator.controllers[sessionID] {
                    ParticipantLoopRow(
                        sessionID: sessionID,
                        controller: controller,
                        sessionManager: sessionManager
                    )
                }
            }

            if showEventLog {
                Divider()
                Text("Event Log")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)

                ForEach(coordinator.groupSession.participantSessionIDs, id: \.self) { sessionID in
                    if let controller = coordinator.controllers[sessionID] {
                        ParticipantEventLog(
                            sessionID: sessionID,
                            controller: controller,
                            sessionManager: sessionManager
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

private struct ParticipantLoopRow: View {
    let sessionID: UUID
    @ObservedObject var controller: ParticipantController
    @ObservedObject var sessionManager: CLISessionManager

    private var name: String {
        sessionManager.sessions
            .first(where: { $0.id == sessionID })?
            .target.name ?? "?"
    }

    private var status: ParticipantDebugStatus {
        controller.debugStatus
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 60, alignment: .leading)
                .lineLimit(1)

            loopBadge("IN", state: status.inputLoop.rawValue, color: inputColor)
            loopBadge("OUT", state: status.outputLoop.rawValue, color: outputColor)

            Text("seen:\(status.lastSeenSequence)/\(status.groupSequence)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)

            if status.isProcessing {
                Text("BUSY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            if status.consecutivePassCount > 0 {
                Text("PASS:\(status.consecutivePassCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            }

            if status.isStableIdle {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .help("Stable idle")
            }

            Spacer()
        }
    }

    private var inputColor: Color {
        switch status.inputLoop {
        case .stopped: return .gray
        case .idle: return .secondary
        case .polling: return .blue
        case .injecting: return .orange
        }
    }

    private var outputColor: Color {
        switch status.outputLoop {
        case .stopped: return .gray
        case .idle: return .secondary
        case .polling: return .blue
        case .capturing: return .green
        }
    }

    private func loopBadge(_ label: String, state: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text(state)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(color.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Participant Event Log

private struct ParticipantEventLog: View {
    let sessionID: UUID
    @ObservedObject var controller: ParticipantController
    @ObservedObject var sessionManager: CLISessionManager

    private var name: String {
        sessionManager.sessions
            .first(where: { $0.id == sessionID })?
            .target.name ?? "?"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if controller.debugEvents.isEmpty {
                Text("(no events)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(controller.debugEvents.suffix(10)) { event in
                    HStack(spacing: 4) {
                        Text(Self.timeFormatter.string(from: event.timestamp))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(event.type.rawValue)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(colorForEventType(event.type))
                        Text(event.detail)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func colorForEventType(_ type: DebugEventType) -> Color {
        switch type {
        case .messageInjected: return .blue
        case .outputCaptured: return .green
        case .passDetected: return .orange
        case .waitingForInput: return .secondary
        case .stableIdleReached: return .mint
        case .noNewMessages: return .secondary
        }
    }
}

private struct ParsedGroupMessage {
    let primaryText: String
    let detailsText: String?

    init(_ raw: String) {
        let text = ParsedGroupMessage.sanitize(raw)
        let lines = text.components(separatedBy: .newlines)

        var visible: [String] = []
        var hidden: [String] = []
        for line in lines {
            if ParsedGroupMessage.isNoiseLine(line) {
                hidden.append(line)
            } else {
                visible.append(line)
            }
        }

        let visibleText = ParsedGroupMessage.trim(visible.joined(separator: "\n"))
        let hiddenText = ParsedGroupMessage.trim(hidden.joined(separator: "\n"))
        primaryText = visibleText.isEmpty ? ParsedGroupMessage.trim(text) : visibleText
        detailsText = hiddenText.isEmpty ? nil : hiddenText
    }

    private static func sanitize(_ text: String) -> String {
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

    private static func isNoiseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return false
        }

        let noisyPrefixes = [
            "╭", "╰", "│",
            "Action Required", "Press ctrl-o", "Waiting for user confirmation",
            "[Group Chat] You are \"", "Full history: ", "New messages since your last response:"
        ]
        if noisyPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        // Status/spinner lines from CLI tools (e.g. "Working(0s • esc to interrupt)")
        if trimmed.contains("Working(") && trimmed.contains("s") { return true }
        if trimmed.contains("esc to interrupt") || trimmed.contains("esc to cancel") { return true }

        return trimmed.contains("ReadFile {") || trimmed.contains("Path not in workspace:")
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
