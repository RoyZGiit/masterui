import Foundation
import Combine

// MARK: - CLISessionManager

/// Manages multiple CLI terminal sessions.
class CLISessionManager: ObservableObject {

    @Published var sessions: [CLISession] = []
    @Published var focusedSessionID: UUID?

    /// Available CLI targets the user can create sessions for.
    var availableCLITargets: [AITarget] {
        guard AppState.shared.cliEnabled else { return [] }
        return AppState.shared.targets.filter { $0.type == .cliTool && $0.isEnabled }
    }

    // MARK: - Session Lifecycle

    @discardableResult
    func createSession(for target: AITarget) -> CLISession {
        let session = CLISession(target: target)
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
}
