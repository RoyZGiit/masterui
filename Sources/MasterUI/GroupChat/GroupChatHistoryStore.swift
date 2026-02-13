import Foundation

// MARK: - GroupChatHistoryFile

/// Codable representation of a group chat for JSON persistence.
struct GroupChatHistoryFile: Codable {
    let chatID: UUID
    let title: String
    let participants: [String]
    var participantSessionIDs: [UUID]?
    let createdAt: Date?
    let updatedAt: Date?
    var messages: [GroupMessage]

    var resolvedCreatedAt: Date {
        createdAt ?? messages.first?.timestamp ?? Date()
    }

    var resolvedUpdatedAt: Date {
        updatedAt ?? messages.last?.timestamp ?? resolvedCreatedAt
    }

    var resolvedParticipantSessionIDs: [UUID] {
        participantSessionIDs ?? []
    }
}

// MARK: - GroupChatHistoryStore

/// Handles JSON-based persistence of group chat history.
class GroupChatHistoryStore {
    static let shared = GroupChatHistoryStore()

    /// Serial queue for disk writes to prevent concurrent overlapping saves.
    private let writeQueue = DispatchQueue(label: "com.masterui.groupchat.historywrite")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
    /// Encoding happens on the calling thread; the file write is dispatched
    /// to a serial queue to prevent concurrent overlapping writes.
    func save(_ session: GroupChatSession) {
        let participantNames = session.messages.reduce(into: Set<String>()) { names, msg in
            if case .ai(let name, _, _) = msg.source {
                names.insert(name)
            }
        }

        let file = GroupChatHistoryFile(
            chatID: session.id,
            title: session.title,
            participants: participantNames.sorted(),
            participantSessionIDs: session.participantSessionIDs,
            createdAt: session.createdAt,
            updatedAt: session.lastActivityDate,
            messages: session.messages.filter(\.persist)
        )

        guard let data = try? encoder.encode(file) else { return }

        let url = Self.groupChatDirectory
            .appendingPathComponent("\(session.id.uuidString).json")

        writeQueue.async { [self] in
            ensureDirectory()
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Loads a group chat history file by ID.
    func load(id: UUID) -> GroupChatHistoryFile? {
        let url = Self.groupChatDirectory
            .appendingPathComponent("\(id.uuidString).json")

        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(GroupChatHistoryFile.self, from: data)
    }

    func delete(id: UUID) {
        let url = Self.groupChatDirectory
            .appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func listAll() -> [GroupChatHistoryFile] {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.groupChatDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(GroupChatHistoryFile.self, from: data)
            }
            .sorted { $0.resolvedUpdatedAt > $1.resolvedUpdatedAt }
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        let dir = Self.groupChatDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
