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
            List {
                ForEach(sessionManager.availableCLITargets) { target in
                    HStack {
                        Image(systemName: target.iconSymbol)
                            .foregroundStyle(Color(hex: target.colorHex) ?? Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(target.name)
                                .font(.system(size: 13, weight: .medium))

                            let isInstalled = FileManager.default.isExecutableFile(atPath: target.executablePath)
                            if isInstalled {
                                Text(target.executablePath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not Installed")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()

                        let isInstalled = FileManager.default.isExecutableFile(atPath: target.executablePath)
                        if !isInstalled {
                            Button("Install Info") {
                                alertTargetName = target.name
                                alertInstallCommand = target.installationGuide ?? "Please check official documentation."
                                showInstallAlert = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if selectedTarget?.id == target.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if FileManager.default.isExecutableFile(atPath: target.executablePath) {
                            selectedTarget = target
                        }
                    }
                }

                if sessionManager.availableCLITargets.isEmpty {
                    Text("No CLI tools configured. Add tools in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Create") {
                    if let target = selectedTarget {
                        sessionManager.createSession(for: target)
                    }
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedTarget == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .alert("Install \(alertTargetName)", isPresented: $showInstallAlert) {
            Button("Copy Command") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(alertInstallCommand, forType: .string)
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Run this command in your terminal:\n\n\(alertInstallCommand)")
        }
    }

    @State private var showInstallAlert = false
    @State private var alertTargetName = ""
    @State private var alertInstallCommand = ""
}
