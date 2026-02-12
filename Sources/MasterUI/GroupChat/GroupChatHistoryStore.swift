import Foundation

// MARK: - GroupChatHistoryFile

/// Codable representation of a group chat for JSON persistence.
struct GroupChatHistoryFile: Codable {
    let chatID: UUID
    let title: String
    let participants: [String]
    var messages: [GroupMessage]
}

// MARK: - GroupChatHistoryStore

/// Handles JSON-based persistence of group chat history.
class GroupChatHistoryStore {
    static let shared = GroupChatHistoryStore()

    private static let groupChatDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui/groupchat")
    }()

    /// Returns the file path for a given group chat session's history.
    func historyFilePath(for session: GroupChatSession) -> String {
        Self.groupChatDirectory
            .appendingPathComponent("\(session.id.uuidString).json")
            .path
    }

    /// Saves the group chat session to a JSON file.
    func save(_ session: GroupChatSession) {
        let fm = FileManager.default
        let dir = Self.groupChatDirectory

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let participantNames = session.messages.reduce(into: Set<String>()) { names, msg in
            if case .ai(let name, _, _) = msg.source {
                names.insert(name)
            }
        }

        let file = GroupChatHistoryFile(
            chatID: session.id,
            title: session.title,
            participants: participantNames.sorted(),
            messages: session.messages
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(file) else { return }

        let url = Self.groupChatDirectory
            .appendingPathComponent("\(session.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    /// Loads a group chat history file by ID.
    func load(id: UUID) -> GroupChatHistoryFile? {
        let url = Self.groupChatDirectory
            .appendingPathComponent("\(id.uuidString).json")

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(GroupChatHistoryFile.self, from: data)
    }
}
