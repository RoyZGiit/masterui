import Foundation

// MARK: - SessionState

enum SessionState: String {
    case starting
    case running
    case waitingForInput
    case exited
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

    /// Whether this session has new activity since last viewed.
    @Published var hasUnreadActivity: Bool = false

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
    }
}
