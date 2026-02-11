import SwiftUI
import UniformTypeIdentifiers

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
            if let session = sessionManager.focusedSession {
                SessionContentView(
                    session: session,
                    onStateChange: { sessionID, state in
                        handleStateChange(sessionID: sessionID, state: state)
                    },
                    onTerminate: { terminateSession($0) },
                    onNewSession: { showNewSessionSheet = true }
                )
            } else {
                noSessionView
            }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewCLISessionSheet(sessionManager: sessionManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCLISession)) { _ in
            showNewSessionSheet = true
        }
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

}

// MARK: - SessionContentView

/// Extracted per-session content view that properly observes the CLISession.
/// This ensures tab switching and history updates trigger re-renders.
private struct SessionContentView: View {
    @ObservedObject var session: CLISession
    var onStateChange: (UUID, SessionState) -> Void
    var onTerminate: (CLISession) -> Void
    var onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Terminal toolbar with tab picker
            toolbar
            Divider()
            // Content area: Terminal or History
            if session.activeTab == .history {
                SessionHistoryView(session: session)
            } else {
                EnhancedTerminalViewWrapper(
                    session: session,
                    onStateChange: { newState in
                        onStateChange(session.id, newState)
                    }
                )
                .id(session.id)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
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

            // Tab picker: Terminal / History
            Picker("", selection: Binding(
                get: { session.activeTab },
                set: { newTab in
                    // Flush pending turn before switching to history
                    if newTab == .history {
                        if let termView = TerminalViewCache.shared.terminalView(for: session.id) {
                            termView.idleCoordinator?.flushPendingTurn(force: true)
                        }
                    }
                    session.activeTab = newTab
                }
            )) {
                Text("Terminal").tag(SessionTab.terminal)
                Text("History").tag(SessionTab.history)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Quick actions
            if session.state != .exited {
                Button(action: { onTerminate(session) }) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Terminate process")
            }

            Button(action: onNewSession) {
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
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTarget: AITarget?
    @State private var selectedDirectoryURL: URL?
    @State private var showDirectoryPicker = false

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Working Directory")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Text(displayWorkingDirectory)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(displayWorkingDirectoryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if hasCustomDirectorySelection {
                        Button {
                            selectedDirectoryURL = nil
                            appState.lastSelectedCLIDirectory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear saved directory")
                    }

                    Button("Choose Folder") {
                        showDirectoryPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Create") {
                    if let target = selectedTarget {
                        sessionManager.createSession(
                            for: target,
                            workingDirectory: resolvedWorkingDirectory
                        )
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
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedDirectoryURL = urls.first
                appState.lastSelectedCLIDirectory = urls.first?.path
            case .failure:
                break
            }
        }
    }

    @State private var showInstallAlert = false
    @State private var alertTargetName = ""
    @State private var alertInstallCommand = ""

    private var resolvedWorkingDirectory: String? {
        if let selectedDirectoryURL {
            return selectedDirectoryURL.path
        }
        if let lastDirectory = appState.lastSelectedCLIDirectory, !lastDirectory.isEmpty {
            return lastDirectory
        }
        if let fallback = selectedTarget?.workingDirectory, !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    private var displayWorkingDirectory: String {
        resolvedWorkingDirectory ?? "Default (~)"
    }

    private var displayWorkingDirectoryColor: Color {
        resolvedWorkingDirectory == nil ? .secondary : .primary
    }

    private var hasCustomDirectorySelection: Bool {
        selectedDirectoryURL != nil || (appState.lastSelectedCLIDirectory?.isEmpty == false)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6, let intVal = UInt64(hexStr, radix: 16) else { return nil }
        self.init(
            red: Double((intVal >> 16) & 0xFF) / 255,
            green: Double((intVal >> 8) & 0xFF) / 255,
            blue: Double(intVal & 0xFF) / 255
        )
    }
}
