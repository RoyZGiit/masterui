import Foundation

// MARK: - GroupMessageSource

/// Identifies who sent a message in a group chat.
enum GroupMessageSource: Codable, Equatable {
    case user
    case ai(name: String, sessionID: UUID, colorHex: String)
    case system

    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .ai(let name, _, _):
            return name
        case .system:
            return "System"
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
    var persist: Bool
    var thinkingProcess: [ThinkingCard]?

    struct ThinkingCard: Codable {
        let kind: String   // "thought" / "action" / "result"
        let text: String
        let ts: Date
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: GroupMessageSource,
        content: String,
        isStreaming: Bool = false,
        persist: Bool = true,
        thinkingProcess: [ThinkingCard]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.content = content
        self.isStreaming = isStreaming
        self.persist = persist
        self.thinkingProcess = thinkingProcess
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case content
        case isStreaming
        case persist
        case thinkingProcess
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(GroupMessageSource.self, forKey: .source)
        content = try container.decode(String.self, forKey: .content)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        persist = try container.decodeIfPresent(Bool.self, forKey: .persist) ?? true
        thinkingProcess = try container.decodeIfPresent([ThinkingCard].self, forKey: .thinkingProcess)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(content, forKey: .content)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(persist, forKey: .persist)
        try container.encodeIfPresent(thinkingProcess, forKey: .thinkingProcess)
    }
}
