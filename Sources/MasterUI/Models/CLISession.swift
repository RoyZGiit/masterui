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
    @Published var isCustomTitle: Bool = false
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
            if let savedTitle = existing.customTitle {
                self.title = savedTitle
                self.isCustomTitle = true
            }
        } else {
            self.history = SessionHistory(
                sessionID: id,
                targetName: target.name,
                workingDirectory: target.workingDirectory,
                createdAt: Date(),
                updatedAt: Date(),
                blocks: []
            )
        }
    }

    /// Append a block and return its id so later output can update the same block.
    @discardableResult
    func appendBlock(role: SessionRole, content: String, timestamp: Date = Date()) -> UUID {
        let block = SessionBlock(
            role: role,
            timestamp: timestamp,
            content: content
        )
        history.blocks.append(block)
        history.updatedAt = Date()
        SessionHistoryStore.shared.save(history)
        return block.id
    }

    /// Replace the content of an existing block.
    func updateBlockContent(blockID: UUID, content: String) {
        guard let idx = history.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        history.blocks[idx] = SessionBlock(
            id: history.blocks[idx].id,
            role: history.blocks[idx].role,
            timestamp: history.blocks[idx].timestamp,
            content: content
        )
        history.updatedAt = Date()
        SessionHistoryStore.shared.save(history)
    }

    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        title = trimmed
        isCustomTitle = true
        history.customTitle = trimmed
        SessionHistoryStore.shared.save(history)
    }
}
