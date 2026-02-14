import Foundation

// MARK: - GroupChatHistoryFile

/// Codable representation of a group chat for JSON persistence.
struct GroupChatHistoryFile: Codable {
    let chatID: UUID
    let title: String
    let participants: [String]
    var participantSessionIDs: [UUID]?
    var participantSessionID: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    var messages: [GroupMessage]

    enum CodingKeys: String, CodingKey {
        case chatID
        case title
        case participants
        case participantSessionIDs
        case participantSessionID
        case createdAt
        case updatedAt
        case messages
    }

    init(
        chatID: UUID,
        title: String,
        participants: [String],
        participantSessionIDs: [UUID]?,
        createdAt: Date?,
        updatedAt: Date?,
        messages: [GroupMessage]
    ) {
        self.chatID = chatID
        self.title = title
        self.participants = participants
        self.participantSessionIDs = participantSessionIDs
        self.participantSessionID = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chatID = try container.decode(UUID.self, forKey: .chatID)
        title = try container.decode(String.self, forKey: .title)
        participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        participantSessionIDs = try container.decodeIfPresent([UUID].self, forKey: .participantSessionIDs)
        participantSessionID = try container.decodeIfPresent(UUID.self, forKey: .participantSessionID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        messages = try container.decodeIfPresent([GroupMessage].self, forKey: .messages) ?? []
    }

    var resolvedCreatedAt: Date {
        createdAt ?? messages.first?.timestamp ?? Date()
    }

    var resolvedUpdatedAt: Date {
        updatedAt ?? messages.last?.timestamp ?? resolvedCreatedAt
    }

    var resolvedParticipantSessionIDs: [UUID] {
        if let ids = participantSessionIDs {
            return ids
        }
        if let legacy = participantSessionID {
            return [legacy]
        }
        return []
    }
}

struct GroupChatHistoryMetadata {
    let chatID: UUID
    let title: String
    let participants: [String]
    let participantSessionIDs: [UUID]
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
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
    private let indexQueue = DispatchQueue(label: "com.masterui.groupchat.historyindex")
    private var metadataIndex: [UUID: GroupChatHistoryMetadata] = [:]
    private static let metadataIndexFileName = "index.json"

    private static let groupChatDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui/groupchat")
    }()

    private init() {
        ensureDirectory()
        loadMetadataIndexFromDisk()
        if metadataIndex.isEmpty {
            rebuildMetadataIndex()
        }
    }

    /// Returns the file path for a given group chat session's history.
    func historyFilePath(for session: GroupChatSession) -> String {
        Self.groupChatDirectory
            .appendingPathComponent("\(session.id.uuidString).json")
            .path
    }

    /// Returns the file path for a given group chat session's debug log.
    func debugLogFilePath(for session: GroupChatSession) -> String {
        Self.groupChatDirectory
            .appendingPathComponent("\(session.id.uuidString).debug.log")
            .path
    }

    /// Saves the group chat session to a JSON file.
    /// Encoding happens on the calling thread.
    /// By default writes are queued on a serial queue; pass `synchronously: true`
    /// when a durable write is required before process exit.
    func save(_ session: GroupChatSession, synchronously: Bool = false) {
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

        let writeBlock = { [self] in
            self.ensureDirectory()
            try? data.write(to: url, options: .atomic)
        }
        indexQueue.sync {
            metadataIndex[session.id] = GroupChatHistoryMetadata(
                chatID: session.id,
                title: session.title,
                participants: participantNames.sorted(),
                participantSessionIDs: session.participantSessionIDs,
                createdAt: session.createdAt,
                updatedAt: session.lastActivityDate,
                messageCount: session.messages.filter(\.persist).count
            )
            persistMetadataIndexLocked()
        }
        if synchronously {
            writeBlock()
        } else {
            writeQueue.async(execute: writeBlock)
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
        indexQueue.sync {
            _ = metadataIndex.removeValue(forKey: id)
            persistMetadataIndexLocked()
        }
    }

    func listAll() -> [GroupChatHistoryFile] {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.groupChatDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.metadataIndexFileName }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(GroupChatHistoryFile.self, from: data)
            }
            .sorted { $0.resolvedUpdatedAt > $1.resolvedUpdatedAt }
    }

    func listAllMetadata() -> [GroupChatHistoryMetadata] {
        indexQueue.sync {
            metadataIndex.values
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        let dir = Self.groupChatDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private struct GroupMessageMetadata: Decodable {
        let timestamp: Date?
    }

    private struct GroupChatHistoryMetadataFile: Decodable {
        let chatID: UUID
        let title: String?
        let participants: [String]?
        let participantSessionIDs: [UUID]?
        let participantSessionID: UUID?
        let createdAt: Date?
        let updatedAt: Date?
        let messages: [GroupMessageMetadata]
    }

    private func rebuildMetadataIndex() {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.groupChatDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        var refreshed: [UUID: GroupChatHistoryMetadata] = [:]
        for url in files where url.pathExtension == "json" && url.lastPathComponent != Self.metadataIndexFileName {
            guard let data = try? Data(contentsOf: url),
                  let metadata = try? decoder.decode(GroupChatHistoryMetadataFile.self, from: data) else {
                continue
            }

            let participantIDs = metadata.participantSessionIDs
                ?? metadata.participantSessionID.map { [$0] }
                ?? []
            let createdAt = metadata.createdAt ?? metadata.messages.first?.timestamp ?? Date()
            let updatedAt = metadata.updatedAt ?? metadata.messages.last?.timestamp ?? createdAt

            refreshed[metadata.chatID] = GroupChatHistoryMetadata(
                chatID: metadata.chatID,
                title: metadata.title ?? "Group Chat",
                participants: metadata.participants ?? [],
                participantSessionIDs: participantIDs,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messageCount: metadata.messages.count
            )
        }

        indexQueue.sync {
            metadataIndex = refreshed
            persistMetadataIndexLocked()
        }
    }

    private struct MetadataIndexRecord: Codable {
        let chatID: UUID
        let title: String
        let participants: [String]
        let participantSessionIDs: [UUID]
        let createdAt: Date
        let updatedAt: Date
        let messageCount: Int
    }

    private struct MetadataIndexFile: Codable {
        let version: Int
        let chats: [MetadataIndexRecord]
    }

    private func metadataIndexFileURL() -> URL {
        Self.groupChatDirectory.appendingPathComponent(Self.metadataIndexFileName)
    }

    private func loadMetadataIndexFromDisk() {
        let url = metadataIndexFileURL()
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(MetadataIndexFile.self, from: data) else {
            return
        }
        let mapped = Dictionary(uniqueKeysWithValues: file.chats.map { record in
            (
                record.chatID,
                GroupChatHistoryMetadata(
                    chatID: record.chatID,
                    title: record.title,
                    participants: record.participants,
                    participantSessionIDs: record.participantSessionIDs,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    messageCount: record.messageCount
                )
            )
        })
        indexQueue.sync {
            metadataIndex = mapped
        }
    }

    private func persistMetadataIndexLocked() {
        let sorted = metadataIndex.values.sorted { $0.updatedAt > $1.updatedAt }
        let file = MetadataIndexFile(
            version: 1,
            chats: sorted.map {
                MetadataIndexRecord(
                    chatID: $0.chatID,
                    title: $0.title,
                    participants: $0.participants,
                    participantSessionIDs: $0.participantSessionIDs,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    messageCount: $0.messageCount
                )
            }
        )
        guard let data = try? encoder.encode(file) else { return }
        ensureDirectory()
        try? data.write(to: metadataIndexFileURL(), options: .atomic)
    }
}
