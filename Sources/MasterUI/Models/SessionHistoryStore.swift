import Foundation

// MARK: - SessionRole

/// Author of a single history block.
enum SessionRole: String, Codable {
    case user
    case assistant
}

// MARK: - SessionBlock

/// A single block in a CLI session history.
struct SessionBlock: Codable, Identifiable {
    var id: UUID = UUID()
    let role: SessionRole
    let timestamp: Date
    let content: String
}

// MARK: - SessionHistory

/// The complete history for a single CLI session, persisted as JSON.
struct SessionHistory: Codable {
    let sessionID: UUID
    let targetName: String
    let workingDirectory: String?
    let createdAt: Date
    var updatedAt: Date
    var blocks: [SessionBlock]
    var customTitle: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case targetName
        case workingDirectory
        case createdAt
        case updatedAt
        case blocks
        case turns
        case customTitle
    }

    /// Legacy persisted format: one item includes both user input and assistant output.
    private struct LegacySessionTurn: Codable {
        let id: UUID?
        let timestamp: Date
        let input: String
        let output: String
    }

    init(
        sessionID: UUID,
        targetName: String,
        workingDirectory: String?,
        createdAt: Date,
        updatedAt: Date,
        blocks: [SessionBlock],
        customTitle: String? = nil
    ) {
        self.sessionID = sessionID
        self.targetName = targetName
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.blocks = blocks
        self.customTitle = customTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        targetName = try container.decode(String.self, forKey: .targetName)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)

        if let decodedBlocks = try container.decodeIfPresent([SessionBlock].self, forKey: .blocks) {
            blocks = decodedBlocks
            return
        }

        let legacyTurns = try container.decodeIfPresent([LegacySessionTurn].self, forKey: .turns) ?? []
        blocks = legacyTurns.flatMap { turn in
            [
                SessionBlock(role: .user, timestamp: turn.timestamp, content: turn.input),
                SessionBlock(role: .assistant, timestamp: turn.timestamp, content: turn.output),
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(targetName, forKey: .targetName)
        try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(blocks, forKey: .blocks)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
    }
}

// MARK: - SessionHistoryStore

/// Reads and writes session history files in `~/.masterui/history/`.
class SessionHistoryStore {
    static let shared = SessionHistoryStore()

    private let historyDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui/history")
    }()

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private init() {
        ensureDirectory()
    }

    // MARK: - CRUD

    func save(_ history: SessionHistory) {
        ensureDirectory()
        let url = fileURL(for: history.sessionID)
        if let data = try? encoder.encode(history) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func load(sessionID: UUID) -> SessionHistory? {
        let url = fileURL(for: sessionID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SessionHistory.self, from: data)
    }

    func delete(sessionID: UUID) {
        let url = fileURL(for: sessionID)
        try? FileManager.default.removeItem(at: url)
    }

    func listAll() -> [SessionHistory] {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SessionHistory.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns the on-disk file path for a session's history JSON.
    func filePath(for sessionID: UUID) -> String {
        fileURL(for: sessionID).path
    }

    // MARK: - Private

    private func fileURL(for sessionID: UUID) -> URL {
        historyDirectory.appendingPathComponent("\(sessionID.uuidString).json")
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: historyDirectory.path) {
            try? fm.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        }
    }
}

// MARK: - ClosedSession

/// Lightweight model representing a closed session for the recycle bin.
struct ClosedSession: Identifiable {
    let id: UUID
    let targetName: String
    let customTitle: String?
    let workingDirectory: String?
    let createdAt: Date
    let updatedAt: Date
    let blockCount: Int

    var displayTitle: String {
        customTitle ?? targetName
    }

    init(from history: SessionHistory) {
        self.id = history.sessionID
        self.targetName = history.targetName
        self.customTitle = history.customTitle
        self.workingDirectory = history.workingDirectory
        self.createdAt = history.createdAt
        self.updatedAt = history.updatedAt
        self.blockCount = history.blocks.count
    }
}
