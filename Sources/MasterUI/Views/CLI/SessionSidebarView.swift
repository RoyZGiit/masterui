import SwiftUI

// MARK: - SessionSidebarView

/// IM-style sidebar listing all CLI sessions.
struct SessionSidebarView: View {
    @ObservedObject var sessionManager: CLISessionManager
    var onRename: (UUID, String) -> Void
    var onReload: (UUID) -> Void
    @State private var showNewSessionSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showNewSessionSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("New Session (Cmd+T)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if sessionManager.sessions.isEmpty {
                emptySidebar
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sessionManager.sessions) { session in
                            SessionRowView(
                                session: session,
                                isSelected: session.id == sessionManager.focusedSessionID,
                                onSelect: { sessionManager.focusSession(session.id) },
                                onRename: { onRename(session.id, $0) },
                                onReload: { onReload(session.id) },
                                onClose: { sessionManager.closeSession(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .sheet(isPresented: $showNewSessionSheet) {
            NewCLISessionSheet(sessionManager: sessionManager)
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
            Button("Close Session", role: .destructive) {
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
