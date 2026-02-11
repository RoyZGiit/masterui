import Foundation

// MARK: - Message

/// A single message in a conversation with an AI target.
struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let role: MessageRole
    var content: String
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        role: MessageRole,
        content: String,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}

// MARK: - MessageRole

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

