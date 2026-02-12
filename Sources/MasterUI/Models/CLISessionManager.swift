import Foundation
import Combine

// MARK: - CLISessionManager

/// Manages multiple CLI terminal sessions.
class CLISessionManager: ObservableObject {
    struct RestorableSession: Codable {
        let targetName: String
        let workingDirectory: String?
    }

    @Published var sessions: [CLISession] = []
    @Published var focusedSessionID: UUID?

    /// Available CLI targets the user can create sessions for.
    var availableCLITargets: [AITarget] {
        guard AppState.shared.cliEnabled else { return [] }
        return AppState.shared.targets.filter { $0.type == .cliTool && $0.isEnabled }
    }

    // MARK: - Session Lifecycle

    @discardableResult
    func createSession(for target: AITarget, workingDirectory: String? = nil) -> CLISession {
        var configuredTarget = target
        if let workingDirectory, !workingDirectory.isEmpty {
            configuredTarget.workingDirectory = workingDirectory
        }

        let session = CLISession(target: configuredTarget)
        sessions.append(session)

        // Auto-focus the new session
        focusedSessionID = session.id

        return session
    }

    func closeSession(_ id: UUID) {
        // Terminate the terminal process and clean up cached view
        TerminalViewCache.shared.remove(sessionID: id)

        sessions.removeAll { $0.id == id }

        // If we closed the focused session, focus the last remaining one
        if focusedSessionID == id {
            focusedSessionID = sessions.last(where: { $0.state != .exited })?.id
        }
    }

    func focusSession(_ id: UUID) {
        focusedSessionID = id

        // Clear unread flag when focused
        if let session = sessions.first(where: { $0.id == id }) {
            session.hasUnreadActivity = false
        }
    }

    func renameSession(_ id: UUID, title: String) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.rename(to: title)
    }

    func reloadSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        // Terminate existing process/view, but keep same session object and history.
        TerminalViewCache.shared.remove(sessionID: id)

        session.state = .starting
        session.exitCode = nil
        session.lastActivityDate = Date()
        session.hasUnreadActivity = false
        session.activeTab = .terminal
        session.currentDirectory = session.target.workingDirectory

        // Keep custom title; otherwise reset to default before process title updates.
        if !session.isCustomTitle {
            session.title = session.target.name
        }

        // Immediately start a fresh process for this same session id.
        _ = TerminalViewCache.shared.getOrCreate(for: session, onStateChange: nil)
    }

    // MARK: - State Queries

    var focusedSession: CLISession? {
        guard let id = focusedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Sessions that are running but not focused — shown in the monitor strip.
    var monitoredSessions: [CLISession] {
        sessions.filter { $0.id != focusedSessionID && $0.state != .exited }
    }

    /// Sessions that are waiting for input (idle).
    var idleSessions: [CLISession] {
        sessions.filter { $0.state == .waitingForInput }
    }

    // MARK: - Notifications

    func sessionBecameIdle(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        session.state = .waitingForInput

        // Mark as unread if not currently focused
        if id != focusedSessionID {
            session.hasUnreadActivity = true
        }
    }

    func sessionBecameActive(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.state = .running
        session.lastActivityDate = Date()
    }

    // MARK: - Persistence

    func restorableSessions() -> [RestorableSession] {
        sessions
            .filter { $0.state != .exited }
            .map {
                RestorableSession(
                    targetName: $0.target.name,
                    workingDirectory: $0.currentDirectory ?? $0.target.workingDirectory
                )
            }
    }

    func restoreSessions(from snapshots: [RestorableSession], targets: [AITarget]) {
        for snapshot in snapshots {
            guard let target = targets.first(where: { $0.name == snapshot.targetName }) else { continue }
            createSession(for: target, workingDirectory: snapshot.workingDirectory)
        }
    }
}
