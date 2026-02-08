import Foundation

// MARK: - Message

/// A single message in a conversation with an AI target.
struct Message: Identifiable, Equatable {
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

// MARK: - Conversation

/// A conversation session with a specific AI target.
class Conversation: ObservableObject, Identifiable {
    let id: UUID
    let targetID: UUID
    @Published var messages: [Message]
    @Published var isActive: Bool

    init(
        id: UUID = UUID(),
        targetID: UUID,
        messages: [Message] = [],
        isActive: Bool = true
    ) {
        self.id = id
        self.targetID = targetID
        self.messages = messages
        self.isActive = isActive
    }

    func addMessage(_ message: Message) {
        messages.append(message)
    }

    func updateLastAssistantMessage(content: String, isStreaming: Bool) {
        if let index = messages.lastIndex(where: { $0.role == .assistant }) {
            messages[index].content = content
            messages[index].isStreaming = isStreaming
        }
    }
}
