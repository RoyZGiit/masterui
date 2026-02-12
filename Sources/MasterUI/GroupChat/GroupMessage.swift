import Foundation

// MARK: - GroupMessageSource

/// Identifies who sent a message in a group chat.
enum GroupMessageSource: Codable, Equatable {
    case user
    case ai(name: String, sessionID: UUID, colorHex: String)

    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .ai(let name, _, _):
            return name
        }
    }
}

// MARK: - GroupMessage

/// A single message in the group chat conversation.
struct GroupMessage: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let source: GroupMessageSource
    var content: String
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: GroupMessageSource,
        content: String,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.isStreaming = isStreaming
    }
}
