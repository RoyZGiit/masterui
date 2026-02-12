import SwiftUI

// MARK: - GroupChatConversationView

/// Displays the unified conversation view for a group chat.
struct GroupChatConversationView: View {
    @ObservedObject var chat: GroupChatSession
    @ObservedObject var coordinator: GroupChatCoordinator
    @ObservedObject var sessionManager: CLISessionManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            conversationHeader

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.messages) { message in
                            GroupMessageBubble(
                                message: message,
                                sessionManager: sessionManager
                            )
                            .id(message.id)
                        }

                        // Active processing indicator
                        if coordinator.isConversationActive {
                            pendingIndicator
                        }
                    }
                    .padding(16)
                }
                .onChange(of: chat.messages.count) {
                    if let lastID = chat.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input — always enabled, user can send at any time
            GroupChatInputBar(
                coordinator: coordinator,
                isWaiting: false
            )
        }
    }

    // MARK: - Header

    private var conversationHeader: some View {
        HStack(spacing: 8) {
            Text(chat.title)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Stop button when conversation is active
            if coordinator.isConversationActive {
                Button(action: { coordinator.stopAll() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop all AI responses")
            }

            // Participant badges
            HStack(spacing: 4) {
                ForEach(chat.participantSessionIDs, id: \.self) { sessionID in
                    if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                        participantBadge(for: session)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func participantBadge(for session: CLISession) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: session.target.colorHex) ?? .gray)
                .frame(width: 6, height: 6)
            Text(session.target.name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    // MARK: - Pending Indicator

    private var pendingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
            Text(pendingNames)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var pendingNames: String {
        let names = coordinator.controllers.values
            .filter { $0.isProcessing }
            .compactMap { $0.cliSession?.target.name }
        if names.isEmpty { return "Thinking..." }
        return names.joined(separator: ", ") + " thinking..."
    }
}

// MARK: - Message Bubble

private struct GroupMessageBubble: View {
    let message: GroupMessage
    let sessionManager: CLISessionManager

    var body: some View {
        switch message.source {
        case .user:
            userBubble
        case .ai(let name, _, let colorHex):
            aiBubble(name: name, colorHex: colorHex)
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 2) {
                Text("You")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        }
    }

    private func aiBubble(name: String, colorHex: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: colorHex) ?? .primary)
                }
                Text(message.content)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 60)
        }
    }

    private var systemBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            Spacer()
        }
    }
}

