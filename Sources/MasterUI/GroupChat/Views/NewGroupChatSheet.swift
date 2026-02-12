import SwiftUI

// MARK: - NewGroupChatSheet

/// Sheet for creating a new group chat by selecting CLI sessions.
struct NewGroupChatSheet: View {
    @ObservedObject var manager: GroupChatManager
    @ObservedObject var sessionManager: CLISessionManager
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var selectedSessionIDs = Set<UUID>()

    private var availableSessions: [CLISession] {
        sessionManager.sessions.filter { $0.state != .exited }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Title field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Group Chat", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }

                // Session picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Participants")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if availableSessions.isEmpty {
                        Text("No active CLI sessions. Create some sessions first.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(availableSessions) { session in
                                SessionSelectionRow(
                                    session: session,
                                    isSelected: selectedSessionIDs.contains(session.id),
                                    onToggle: {
                                        if selectedSessionIDs.contains(session.id) {
                                            selectedSessionIDs.remove(session.id)
                                        } else {
                                            selectedSessionIDs.insert(session.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)

            Spacer()

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    createGroupChat()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSessionIDs.count < 2)
                .keyboardShortcut(.return)
            }
            .padding(16)
        }
        .frame(width: 360, height: 420)
    }

    private func createGroupChat() {
        let chatTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = chatTitle.isEmpty ? "Group Chat" : chatTitle

        manager.createGroupChat(
            title: finalTitle,
            participantSessionIDs: Array(selectedSessionIDs),
            sessionManager: sessionManager
        )
        isPresented = false
    }
}

// MARK: - Session Selection Row

private struct SessionSelectionRow: View {
    let session: CLISession
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Circle()
                    .fill(Color(hex: session.target.colorHex) ?? .gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(session.target.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(session.state.rawValue)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .starting: return .yellow
        case .running: return .green
        case .waitingForInput: return .orange
        case .exited: return .gray
        }
    }
}
