import Foundation

// MARK: - SessionTurn

/// A single turn in a CLI session: one user input + the model's final output.
struct SessionTurn: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let input: String
    let output: String
}

// MARK: - SessionHistory

/// The complete history for a single CLI session, persisted as JSON.
struct SessionHistory: Codable {
    let sessionID: UUID
    let targetName: String
    let workingDirectory: String?
    let createdAt: Date
    var updatedAt: Date
    var turns: [SessionTurn]
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
