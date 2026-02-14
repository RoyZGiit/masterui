import SwiftUI

// MARK: - NewGroupChatSheet

private struct PendingGroupSessionItem: Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
}

/// Sheet for creating a new group chat with mixed existing/new participant sessions.
struct NewGroupChatSheet: View {
    @ObservedObject var manager: GroupChatManager
    @ObservedObject var sessionManager: CLISessionManager
    @ObservedObject private var appState = AppState.shared
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var sessionSearch = ""
    @State private var pendingItems: [PendingGroupSessionItem] = []
    @State private var isCreating = false
    @State private var submitError: String?
    @State private var showNewSessionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Group Chat")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Group Chat", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }

                HStack(alignment: .top, spacing: 12) {
                    existingSessionSelector
                    selectedSessionList
                }

                if let submitError, !submitError.isEmpty {
                    Text(submitError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button(isCreating ? "Creating..." : "Create Group Chat") {
                    createGroupChat()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 760, height: 520)
        .onAppear {
            bootstrapDefaultSessionSelection()
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewCLISessionSheet(sessionManager: sessionManager) { createdSession in
                pendingItems.append(
                    PendingGroupSessionItem(id: UUID(), sessionID: createdSession.id)
                )
            }
        }
    }

    private func createGroupChat() {
        guard canSubmit else { return }
        guard !isCreating else { return }

        submitError = nil
        isCreating = true
        defer { isCreating = false }

        let participantIDs = pendingItems.map(\.sessionID)
        guard !participantIDs.isEmpty else {
            submitError = "Select or create at least 1 session."
            return
        }

        let chatTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = chatTitle.isEmpty ? "Group Chat" : chatTitle

        manager.createGroupChat(
            title: finalTitle,
            participantSessionIDs: participantIDs,
            sessionManager: sessionManager
        )
        appState.viewMode = .groupChat
        isPresented = false
    }

    private var existingSessionSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Sessions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search sessions", text: $sessionSearch)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            ScrollView {
                LazyVStack(spacing: 4) {
                    if filteredExistingSessions.isEmpty {
                        Text("No sessions found")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredExistingSessions) { session in
                            Button(action: { toggleExistingSession(session.id) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: isExistingSelected(session.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(isExistingSelected(session.id) ? Color.accentColor : .secondary)
                                    Text(session.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isExistingSelected(session.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var selectedSessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showNewSessionSheet = true }) {
                    Label("New Session", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if pendingItems.isEmpty {
                        Text("Select or create at least 1 session")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach($pendingItems) { $item in
                            pendingItemRow(item: $item)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func pendingItemRow(item: Binding<PendingGroupSessionItem>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(sessionTitle(for: item.wrappedValue.sessionID))
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()

            Button(action: { removePendingItem(item.wrappedValue.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var filteredExistingSessions: [CLISession] {
        let query = sessionSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return sessionManager.sessions }
        return sessionManager.sessions.filter { session in
            session.title.lowercased().contains(query)
        }
    }

    private var canSubmit: Bool {
        !isCreating && !pendingItems.isEmpty
    }

    private func bootstrapDefaultSessionSelection() {
        guard pendingItems.isEmpty else { return }
        guard let focusedSessionID = sessionManager.focusedSessionID else { return }
        pendingItems.append(
            PendingGroupSessionItem(id: UUID(), sessionID: focusedSessionID)
        )
    }

    private func isExistingSelected(_ sessionID: UUID) -> Bool {
        pendingItems.contains { $0.sessionID == sessionID }
    }

    private func toggleExistingSession(_ sessionID: UUID) {
        if let index = pendingItems.firstIndex(where: { $0.sessionID == sessionID }) {
            pendingItems.remove(at: index)
            return
        }
        pendingItems.append(
            PendingGroupSessionItem(id: UUID(), sessionID: sessionID)
        )
    }

    private func removePendingItem(_ id: UUID) {
        pendingItems.removeAll { $0.id == id }
    }

    private func sessionTitle(for id: UUID) -> String {
        sessionManager.sessions.first(where: { $0.id == id })?.title ?? "Unknown Session"
    }
}
