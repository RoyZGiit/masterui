import SwiftUI

// MARK: - ConversationView

/// Displays the conversation history as chat bubbles.
struct ConversationView: View {
    @ObservedObject var conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if conversation.messages.isEmpty {
                        welcomeMessage
                    } else {
                        ForEach(conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                // Scroll to bottom when new message appears
                if let lastMessage = conversation.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeMessage: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "ellipsis.message")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Start a conversation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Type a message below and it will be sent to the selected AI app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if message.role == .assistant {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                    }
                    Text(message.role == .user ? "You" : "AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                // Message content
                Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(message.content.isEmpty && message.isStreaming ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else {
            return AnyShapeStyle(Color.primary.opacity(0.06))
        }
    }
}
