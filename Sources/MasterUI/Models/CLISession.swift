import Foundation

// MARK: - SessionState

enum SessionState: String {
    case starting
    case running
    case waitingForInput
    case exited
}

// MARK: - SessionTab

enum SessionTab {
    case terminal
    case history
}

// MARK: - CLISession

/// Represents a single CLI terminal session with its own PTY process.
class CLISession: ObservableObject, Identifiable {
    let id: UUID
    let target: AITarget
    let createdAt: Date

    @Published var state: SessionState = .starting
    @Published var title: String
    @Published var lastActivityDate: Date
    @Published var exitCode: Int32?
    @Published var currentDirectory: String?

    /// Whether this session has new activity since last viewed.
    @Published var hasUnreadActivity: Bool = false

    /// Active tab in the session view (terminal or history).
    @Published var activeTab: SessionTab = .terminal

    /// In-memory session history (turns captured from terminal).
    @Published var history: SessionHistory

    init(
        id: UUID = UUID(),
        target: AITarget,
        title: String? = nil
    ) {
        self.id = id
        self.target = target
        self.createdAt = Date()
        self.title = title ?? target.name
        self.lastActivityDate = Date()
        self.currentDirectory = target.workingDirectory

        // Try to load existing history or create empty
        if let existing = SessionHistoryStore.shared.load(sessionID: id) {
            self.history = existing
        } else {
            self.history = SessionHistory(
                sessionID: id,
                targetName: target.name,
                workingDirectory: target.workingDirectory,
                createdAt: Date(),
                updatedAt: Date(),
                turns: []
            )
        }
    }

    /// Append a captured turn (user input + cleaned output) to the history.
    func appendTurn(input: String, output: String) {
        let turn = SessionTurn(
            timestamp: Date(),
            input: input,
            output: output
        )
        history.turns.append(turn)
        history.updatedAt = Date()

        // Persist immediately
        SessionHistoryStore.shared.save(history)
    }
}
