import SwiftUI

// MARK: - CLILayoutView

/// The main layout container for CLI terminal sessions.
/// Uses HSplitView with a sidebar (IM-style session list) and terminal area.
struct CLILayoutView: View {
    @ObservedObject var sessionManager: CLISessionManager
    @State private var showNewSessionSheet = false

    var body: some View {
        HSplitView {
            // Left: Session sidebar
            SessionSidebarView(sessionManager: sessionManager)
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

            // Right: Terminal area
            VStack(spacing: 0) {
                if let session = sessionManager.focusedSession {
                    // Terminal toolbar
                    terminalToolbar(for: session)
                    Divider()
                    // Terminal view — .id() forces recreation when focused session changes
                    EnhancedTerminalViewWrapper(
                        session: session,
                        onStateChange: { newState in
                            handleStateChange(sessionID: session.id, state: newState)
                        }
                    )
                    .id(session.id)
                } else {
                    noSessionView
                }
            }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewCLISessionSheet(sessionManager: sessionManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCLISession)) { _ in
            showNewSessionSheet = true
        }
    }

    // MARK: - Terminal Toolbar

    private func terminalToolbar(for session: CLISession) -> some View {
        HStack(spacing: 8) {
            // Session icon + state
            Circle()
                .fill(stateColor(for: session.state))
                .frame(width: 8, height: 8)

            Text(session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            if session.state == .waitingForInput {
                Text("waiting for input")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            // Quick actions
            if session.state != .exited {
                Button(action: { terminateSession(session) }) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Terminate process")
            }

            Button(action: { showNewSessionSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Session (Cmd+T)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var noSessionView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Active Terminal Sessions")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Create a new session to start interacting with a CLI tool.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button(action: { showNewSessionSheet = true }) {
                Label("New Session", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func handleStateChange(sessionID: UUID, state: SessionState) {
        switch state {
        case .waitingForInput:
            sessionManager.sessionBecameIdle(sessionID)
        case .running:
            sessionManager.sessionBecameActive(sessionID)
        default:
            break
        }
    }

    private func terminateSession(_ session: CLISession) {
        // The terminal view wrapper handles termination through the NSView
        // For now we just close the session from our manager
        sessionManager.closeSession(session.id)
    }

    private func stateColor(for state: SessionState) -> Color {
        switch state {
        case .starting: return .yellow
        case .running: return .green
        case .waitingForInput: return .orange
        case .exited: return .gray
        }
    }
}

// MARK: - NewCLISessionSheet

/// Sheet for creating a new CLI session.
struct NewCLISessionSheet: View {
    @ObservedObject var sessionManager: CLISessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTarget: AITarget?
    @State private var customName = ""
    @State private var customPath = ""
    @State private var customArgs = ""
    @State private var customWorkDir = ""
    @State private var useCustom = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Terminal Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("From Presets") {
                    ForEach(sessionManager.availableCLITargets) { target in
                        HStack {
                            Image(systemName: target.iconSymbol)
                                .foregroundStyle(Color(hex: target.colorHex) ?? Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(target.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(target.executablePath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTarget?.id == target.id && !useCustom {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTarget = target
                            useCustom = false
                        }
                    }

                    if sessionManager.availableCLITargets.isEmpty {
                        Text("No CLI targets configured. Add one in Settings or use custom below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Custom") {
                    Toggle("Use custom command", isOn: $useCustom)
                    if useCustom {
                        TextField("Name", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Executable Path", text: $customPath)
                            .textFieldStyle(.roundedBorder)
                            .help("e.g., /usr/local/bin/claude")
                        TextField("Arguments", text: $customArgs)
                            .textFieldStyle(.roundedBorder)
                            .help("Space-separated")
                        TextField("Working Directory", text: $customWorkDir)
                            .textFieldStyle(.roundedBorder)
                            .help("Optional")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Create") {
                    createSession()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canCreate)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }

    private var canCreate: Bool {
        if useCustom {
            return !customName.isEmpty && !customPath.isEmpty
        }
        return selectedTarget != nil
    }

    private func createSession() {
        if useCustom {
            let args = customArgs.split(separator: " ").map(String.init)
            let target = AITarget(
                name: customName,
                type: .cliTool,
                executablePath: customPath,
                arguments: args,
                workingDirectory: customWorkDir.isEmpty ? nil : customWorkDir,
                iconSymbol: "terminal.fill",
                colorHex: "#4ECDC4"
            )
            sessionManager.createSession(for: target)
        } else if let target = selectedTarget {
            sessionManager.createSession(for: target)
        }
    }
}
