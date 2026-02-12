import SwiftUI

// MARK: - GroupChatLayoutView

/// Main layout for the group chat feature: sidebar + conversation area.
struct GroupChatLayoutView: View {
    @ObservedObject var manager: GroupChatManager
    @ObservedObject var sessionManager: CLISessionManager
    @State private var showingNewGroupChat = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

            mainArea
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Group Chats")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showingNewGroupChat = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Group Chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if manager.groupChats.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No group chats yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: Binding(
                    get: { manager.activeGroupChatID },
                    set: { id in
                        if let id = id {
                            manager.focusGroupChat(id)
                        }
                    }
                )) {
                    ForEach(manager.groupChats) { chat in
                        GroupChatSidebarRow(chat: chat)
                            .tag(chat.id)
                            .contextMenu {
                                Button("Close", role: .destructive) {
                                    manager.closeGroupChat(id: chat.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $showingNewGroupChat) {
            NewGroupChatSheet(
                manager: manager,
                sessionManager: sessionManager,
                isPresented: $showingNewGroupChat
            )
        }
    }

    // MARK: - Main Area

    private var mainArea: some View {
        Group {
            if let chat = manager.activeGroupChat,
               let coordinator = manager.coordinator(for: chat.id) {
                GroupChatConversationView(
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
                    Button("New Group Chat") {
                        showingNewGroupChat = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Sidebar Row

private struct GroupChatSidebarRow: View {
    @ObservedObject var chat: GroupChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text("\(chat.participantSessionIDs.count) participants")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
