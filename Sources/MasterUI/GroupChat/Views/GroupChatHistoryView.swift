import SwiftUI

struct GroupChatHistoryView: View {
    @ObservedObject var chat: GroupChatSession

    var body: some View {
        if chat.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.messages) { message in
                            GroupHistoryMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No History Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Messages will appear here as this\ngroup chat progresses.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GroupHistoryMessageRow: View {
    let message: GroupMessage

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }

    private var senderLabel: String {
        switch message.source {
        case .user:
            return "You"
        case .ai(let name, _, _):
            return name
        case .system:
            return "System"
        }
    }

    private var bubbleColor: Color {
        switch message.source {
        case .user:
            return Color.accentColor.opacity(0.1)
        case .ai:
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        case .system:
            return Color.secondary.opacity(0.1)
        }
    }

    private var contentFont: Font {
        switch message.source {
        case .user:
            return .system(size: 12)
        case .ai:
            return .system(size: 12, design: .monospaced)
        case .system:
            return .system(size: 12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(senderLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(message.content)
                .font(contentFont)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
