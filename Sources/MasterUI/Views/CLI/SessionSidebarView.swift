import SwiftUI

// MARK: - SidebarItem

enum SidebarItem: Identifiable, Hashable {
    case cli(UUID)
    case group(UUID)

    var id: String {
        switch self {
        case .cli(let uuid): return "cli-\(uuid.uuidString)"
        case .group(let uuid): return "group-\(uuid.uuidString)"
        }
    }

    var uuid: UUID {
        switch self {
        case .cli(let uuid): return uuid
        case .group(let uuid): return uuid
        }
    }
}

// MARK: - SessionSidebarView

/// IM-style sidebar listing all CLI sessions and Group chats.
struct SessionSidebarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject private var sessionManager = AppState.shared.cliSessionManager
    @ObservedObject private var groupChatManager = AppState.shared.groupChatManager
    var onRename: (UUID, String) -> Void
    var onReload: (UUID) -> Void
    var onSelectClosedSession: ((ClosedSession) -> Void)?
    @State private var showNewSessionSheet = false
    @State private var showNewGroupChatSheet = false
    @State private var closedSectionExpanded = true

    private var groupChatSessionIDs: Set<UUID> {
        var ids = Set<UUID>()
        for chat in groupChatManager.groupChats {
            for id in chat.participantSessionIDs {
                ids.insert(id)
            }
        }
        return ids
    }

    private var sortedItems: [SidebarItem] {
        let grouped = groupChatSessionIDs
        let cliItems = sessionManager.sessions
            .filter { !grouped.contains($0.id) }
            .map { (SidebarItem.cli($0.id), cliSortDate(for: $0)) }
        let groupItems = groupChatManager.groupChats.map { (SidebarItem.group($0.id), groupSortDate(for: $0)) }

        return (cliItems + groupItems)
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id > $1.0.id
            }
            .map { $0.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chats")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                
                Menu {
                    Button(action: { showNewSessionSheet = true }) {
                        Label("New Session", systemImage: "terminal")
                    }
                    Button(action: { showNewGroupChatSheet = true }) {
                        Label("New Group Chat", systemImage: "person.3")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .help("New Session or Group Chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if sortedItems.isEmpty &&
                sessionManager.closedSessions.isEmpty &&
                groupChatManager.closedGroupChats.isEmpty {
                emptySidebar
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedItems) { item in
                            switch item {
                            case .cli(let id):
                                if let session = sessionManager.sessions.first(where: { $0.id == id }) {
                                    SessionRowView(
                                        session: session,
                                        isSelected: appState.viewMode == .cliSessions && session.id == sessionManager.focusedSessionID,
                                        onSelect: {
                                            appState.viewMode = .cliSessions
                                            sessionManager.focusSession(session.id)
                                        },
                                        onRename: { onRename(session.id, $0) },
                                        onReload: { onReload(session.id) },
                                        onClose: { sessionManager.closeSession(session.id) }
                                    )
                                }
                            case .group(let id):
                                if let chat = groupChatManager.groupChats.first(where: { $0.id == id }) {
                                    GroupChatRowView(
                                        chat: chat,
                                        sessionManager: sessionManager,
                                        groupChatManager: groupChatManager,
                                        isSelected: appState.viewMode == .groupChat && chat.id == groupChatManager.activeGroupChatID,
                                        onSelect: {
                                            appState.viewMode = .groupChat
                                            groupChatManager.focusGroupChat(chat.id)
                                        },
                                        onClose: {
                                            groupChatManager.closeGroupChat(id: chat.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    // Recently Closed section
                    if !sessionManager.closedSessions.isEmpty || !groupChatManager.closedGroupChats.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        DisclosureGroup(isExpanded: $closedSectionExpanded) {
                            LazyVStack(spacing: 2) {
                                ForEach(groupChatManager.closedGroupChats) { closed in
                                    ClosedGroupChatRowView(
                                        closedGroupChat: closed,
                                        canRestore: groupChatManager.canRestoreClosedGroupChat(
                                            closed.id,
                                            sessionManager: sessionManager
                                        ),
                                        onRestore: {
                                            let restored = groupChatManager.restoreClosedGroupChat(
                                                closed.id,
                                                sessionManager: sessionManager
                                            )
                                            if restored {
                                                appState.viewMode = .groupChat
                                            }
                                        },
                                        onDelete: { groupChatManager.permanentlyDeleteClosedGroupChat(closed.id) }
                                    )
                                }

                                ForEach(sessionManager.closedSessions) { closed in
                                    ClosedSessionRowView(
                                        closedSession: closed,
                                        canRestore: sessionManager.canRestoreClosedSession(closed.id),
                                        onSelect: { onSelectClosedSession?(closed) },
                                        onRestore: { _ = sessionManager.restoreClosedSession(closed.id) },
                                        onDelete: { sessionManager.permanentlyDeleteClosedSession(closed.id) }
                                    )
                                }
                            }

                            Button(action: {
                                groupChatManager.clearAllClosedGroupChats()
                                sessionManager.clearAllClosedSessions()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                    Text("Clear All")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 10))
                                Text("Recently Closed")
                                    .font(.system(size: 11, weight: .medium))
                                Text("\(sessionManager.closedSessions.count + groupChatManager.closedGroupChats.count)")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .sheet(isPresented: $showNewSessionSheet) {
            NewCLISessionSheet(sessionManager: sessionManager)
        }
        .sheet(isPresented: $showNewGroupChatSheet) {
            NewGroupChatSheet(
                manager: groupChatManager,
                sessionManager: sessionManager,
                isPresented: $showNewGroupChatSheet
            )
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No sessions")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button("New Session") { showNewSessionSheet = true }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func cliSortDate(for session: CLISession) -> Date {
        session.history.blocks.last?.timestamp ?? session.history.updatedAt
    }

    private func groupSortDate(for chat: GroupChatSession) -> Date {
        chat.messages.last?.timestamp ?? chat.createdAt
    }
}

// MARK: - SessionRowView

/// Individual row in the session sidebar.
struct SessionRowView: View {
    @ObservedObject var session: CLISession
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onReload: () -> Void
    let onClose: () -> Void
    var closeLabel: String = "Close Session"
    @State private var isHovering = false
    @State private var showRenameAlert = false
    @State private var renameDraft = ""

    var body: some View {
        HStack(spacing: 8) {
            // State indicator
            stateIndicator

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)

                    if session.hasUnreadActivity {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(stateLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Time since last activity
            Text(session.lastActivityDate, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .lineLimit(1)

            // Close button on hover
            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) :
                      isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Rename Session") {
                renameDraft = session.title
                showRenameAlert = true
            }
            Button("Reload Session") {
                onReload()
            }
            Divider()
            Button(closeLabel, role: .destructive) {
                onClose()
            }
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Session title", text: $renameDraft)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                onRename(renameDraft)
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Set a custom name for this session.")
        }
    }

    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .overlay(
                session.state == .waitingForInput ?
                    Circle().stroke(Color.orange, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    : nil
            )
    }

    private var stateColor: Color {
        switch session.state {
        case .starting: return .yellow
        case .running: return .green
        case .waitingForInput: return .orange
        case .exited: return .gray
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .starting: return "Starting..."
        case .running: return "Running"
        case .waitingForInput: return "Waiting for input"
        case .exited:
            if let code = session.exitCode {
                return "Exited (\(code))"
            }
            return "Exited"
        }
    }
}

// MARK: - GroupChatRowView

struct GroupChatRowView: View {
    @ObservedObject var chat: GroupChatSession
    @ObservedObject var sessionManager: CLISessionManager
    @ObservedObject var groupChatManager: GroupChatManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var showNewParticipantSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Main group chat row
            HStack(spacing: 8) {
                // Expand arrow
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 12)

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 24, height: 24)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                }

                // Chat info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(chat.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)

                        if chat.hasUnreadActivity {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }

                    // Compact status summary
                    Text(statusSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Time
                Text(chat.lastActivityDate, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)

                // Close button on hover
                if isHovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) :
                          isHovering ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onHover { hovering in isHovering = hovering }
            .contextMenu {
                Button("Close Group Chat", role: .destructive) { onClose() }
            }

            // Expanded child list
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(chat.participantSessionIDs, id: \.self) { sessionID in
                        if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
                            SessionRowView(
                                session: session,
                                isSelected: AppState.shared.viewMode == .cliSessions && session.id == sessionManager.focusedSessionID,
                                onSelect: {
                                    AppState.shared.viewMode = .cliSessions
                                    sessionManager.focusSession(session.id)
                                },
                                onRename: { newName in
                                    session.title = newName
                                },
                                onReload: {
                                    // no-op for group child
                                },
                                onClose: {
                                    _ = groupChatManager.removeParticipantSession(groupChatID: chat.id, sessionID: sessionID)
                                },
                                closeLabel: "Remove from Group"
                            )
                        }
                    }

                    // Add participant button
                    Button { showNewParticipantSheet = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("Add Session")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 34)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
                .sheet(isPresented: $showNewParticipantSheet) {
                    NewGroupParticipantSessionSheet(
                        groupManager: groupChatManager,
                        groupChat: chat,
                        sessionManager: sessionManager,
                        isPresented: $showNewParticipantSheet
                    )
                }
            }
        }
    }

    private var statusSummary: String {
        let activeCount = chat.participantSessionIDs.filter { id in
            if let coordinator = groupChatManager.coordinator(for: chat.id),
               let controller = coordinator.controllers[id] {
                return controller.isProcessing
            }
            return false
        }.count
        let total = chat.participantSessionIDs.count
        if activeCount > 0 {
            return "\(activeCount)/\(total) active"
        }
        return "\(total) participants"
    }
}

// MARK: - ClosedSessionRowView

/// Row for a closed session in the recycle bin section.
struct ClosedSessionRowView: View {
    let closedSession: ClosedSession
    let canRestore: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(closedSession.displayTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text(closedSession.targetName)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    if closedSession.blockCount > 0 {
                        Text("\(closedSession.blockCount) blocks")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            Spacer()

            Text(closedSession.updatedAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .lineLimit(1)

            if isHovering {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(canRestore ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canRestore)
                .help(canRestore ? "Restore session" : "Cannot restore: target unavailable")

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete permanently")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("View History") {
                onSelect()
            }
            Button("Restore Session") {
                onRestore()
            }
            .disabled(!canRestore)
            Divider()
            Button("Delete Permanently", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - ClosedGroupChatRowView

/// Row for a closed group chat in the recycle bin section.
struct ClosedGroupChatRowView: View {
    let closedGroupChat: ClosedGroupChat
    let canRestore: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(closedGroupChat.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("\(closedGroupChat.participantSessionIDs.count) participants")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    if closedGroupChat.messageCount > 0 {
                        Text("\(closedGroupChat.messageCount) messages")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            Spacer()

            Text(closedGroupChat.updatedAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .lineLimit(1)

            if isHovering {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(canRestore ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canRestore)
                .help(canRestore ? "Restore group chat" : "Cannot restore: participant sessions unavailable")

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete permanently")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Restore Group Chat") {
                onRestore()
            }
            .disabled(!canRestore)
            Divider()
            Button("Delete Permanently", role: .destructive) {
                onDelete()
            }
        }
    }
}
