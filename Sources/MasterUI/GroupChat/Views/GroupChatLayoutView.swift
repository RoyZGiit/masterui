import SwiftUI
import AppKit

// MARK: - GroupChatMainArea

/// Main area for the group chat feature: conversation area.
struct GroupChatMainArea: View {
    @ObservedObject var manager: GroupChatManager
    @ObservedObject var sessionManager: CLISessionManager

    var body: some View {
        Group {
            if let chat = manager.activeGroupChat,
               let coordinator = manager.coordinator(for: chat.id) {
                GroupChatContentView(
                    chat: chat,
                    coordinator: coordinator,
                    sessionManager: sessionManager
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Select or create a group chat")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct GroupChatContentView: View {
    @ObservedObject var chat: GroupChatSession
    @ObservedObject var coordinator: GroupChatCoordinator
    @ObservedObject var sessionManager: CLISessionManager
    @State private var showCopiedHistoryPath = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if chat.activeTab == .history {
                GroupChatHistoryView(chat: chat)
            } else {
                GroupChatConversationView(
                    chat: chat,
                    coordinator: coordinator,
                    sessionManager: sessionManager
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.purple)
                .frame(width: 8, height: 8)

            Text(chat.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text("\(chat.participantSessionIDs.count) participants")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $chat.activeTab) {
                Text("Conversation").tag(GroupChatTab.conversation)
                Text("History").tag(GroupChatTab.history)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Button {
                if let path = historyPath {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                    showCopiedHistoryPath = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedHistoryPath = false
                    }
                }
            } label: {
                Image(systemName: showCopiedHistoryPath ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(showCopiedHistoryPath ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(historyPath.map { "Copy history file path: \($0)" } ?? "History file path unavailable")
            .disabled(historyPath == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var historyPath: String? {
        GroupChatHistoryStore.shared.historyFilePath(for: chat)
    }
}
