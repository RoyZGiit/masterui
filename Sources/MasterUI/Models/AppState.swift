import Foundation
import SwiftUI

// MARK: - AppState

/// Global application state, managing targets, conversations, and settings.
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published State

    /// All configured AI targets (derived from CLI configs).
    @Published var targets: [AITarget] = []

    /// Whether CLI tools are enabled.
    @Published var cliEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cliEnabled, forKey: "cliEnabled")
        }
    }

    /// Currently selected target for sending messages.
    @Published var selectedTargetID: UUID?

    /// Whether the app is in element picker mode.
    @Published var isPickingElement: Bool = false

    /// The element picker step (input or output).
    @Published var pickerStep: ElementPickerStep = .selectInput

    /// The target being configured in the element picker.
    @Published var pickerTargetID: UUID?

    /// Current view mode.
    @Published var viewMode: ViewMode = .cliSessions

    /// CLI session manager for terminal sessions.
    @Published var cliSessionManager = CLISessionManager()

    /// Group chat manager for multi-AI conversations.
    @Published var groupChatManager = GroupChatManager()

    /// Last folder chosen in "New Terminal Session".
    @Published var lastSelectedCLIDirectory: String? {
        didSet {
            UserDefaults.standard.set(lastSelectedCLIDirectory, forKey: Self.lastCLIDirectoryKey)
        }
    }

    // MARK: - Private

    private let configFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui_config.json")
    }()
    private let cliSessionsFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui_cli_sessions.json")
    }()
    private let groupChatsFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui_group_chats.json")
    }()
    private static let lastCLIDirectoryKey = "lastSelectedCLIDirectory"
    private struct CLISessionPersistenceSnapshot: Codable {
        let sessions: [CLISessionManager.RestorableSession]
        let focusedSessionID: UUID?
    }
    private struct GroupChatPersistenceSnapshot: Codable {
        let activeGroupChatIDs: [UUID]
        let activeGroupChatID: UUID?
    }

    // MARK: - Init

    private init() {
        // Load cliEnabled from UserDefaults (default true)
        self.cliEnabled = UserDefaults.standard.object(forKey: "cliEnabled") as? Bool ?? true
        self.lastSelectedCLIDirectory = UserDefaults.standard.string(forKey: Self.lastCLIDirectoryKey)

        let configs = loadCLIConfigs()
        if configs.isEmpty {
            // First launch — generate defaults and save
            let defaults = PresetTargets.defaultCLIConfigs()
            saveCLIConfigs(defaults)
            targets = aiTargets(from: defaults)
        } else {
            targets = aiTargets(from: configs)
        }

        selectedTargetID = targets.first(where: { $0.isEnabled })?.id

        restorePersistedCLISessions()
        restorePersistedGroupChats()
        cliSessionManager.refreshClosedSessions()
        groupChatManager.refreshClosedGroupChats()

        // Set up persistence listener AFTER initial restoration to avoid redundant writes
        cliSessionManager.onSessionsChanged = { [weak self] in
            self?.saveCLISessionSnapshots()
        }
        groupChatManager.onStateChanged = { [weak self] in
            self?.saveGroupChatSnapshot()
        }
    }

    // MARK: - CLIToolConfig <-> AITarget conversion

    /// Convert CLIToolConfigs to AITargets, enriching with preset metadata.
    func aiTargets(from configs: [CLIToolConfig]) -> [AITarget] {
        return configs.map { config in
            let meta = PresetTargets.metadata(for: config.name)
            return AITarget(
                name: config.name,
                type: .cliTool,
                executablePath: config.path,
                arguments: config.args,
                workingDirectory: config.workdir,
                iconSymbol: meta?.icon ?? "terminal.fill",
                colorHex: meta?.color ?? "#4ECDC4",
                installationGuide: meta?.installGuide
            )
        }
    }

    // MARK: - Target Management

    var selectedTarget: AITarget? {
        guard let id = selectedTargetID else { return nil }
        return targets.first(where: { $0.id == id })
    }

    var enabledTargets: [AITarget] {
        targets.filter { $0.isEnabled }
    }

    func updateTarget(_ target: AITarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
        }
    }

    func selectTarget(_ id: UUID) {
        selectedTargetID = id
    }

    /// Apply new CLI configs: save to disk and rebuild targets.
    func applyCLIConfigs(_ configs: [CLIToolConfig]) {
        saveCLIConfigs(configs)
        targets = aiTargets(from: configs)
        selectedTargetID = targets.first(where: { $0.isEnabled })?.id
    }

    // MARK: - Persistence

    func persistRuntimeState() {
        saveCLISessionSnapshots()
        saveGroupChatSnapshot()
        saveAllSessionHistories()
        saveAllGroupChatHistories()
    }

    private func saveAllSessionHistories() {
        for session in cliSessionManager.sessions {
            // Flush any pending turn via the terminal coordinator
            if let termView = TerminalViewCache.shared.terminalView(for: session.id) {
                termView.idleCoordinator?.flushPendingTurn(force: true)
            }
            // Save history to disk
            SessionHistoryStore.shared.save(session.history)
        }
    }

    private func saveAllGroupChatHistories() {
        for chat in groupChatManager.groupChats {
            GroupChatHistoryStore.shared.save(chat, synchronously: true)
        }
    }

    func saveCLIConfigs(_ configs: [CLIToolConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(configs) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    func loadCLIConfigs() -> [CLIToolConfig] {
        guard let data = try? Data(contentsOf: configFileURL) else { return [] }

        // Try new format first
        if let configs = try? JSONDecoder().decode([CLIToolConfig].self, from: data) {
            return configs
        }

        // Backward compat: migrate from old [AITarget] format
        if let oldTargets = try? JSONDecoder().decode([AITarget].self, from: data) {
            let configs = oldTargets
                .filter { $0.type == .cliTool }
                .map { CLIToolConfig(name: $0.name, path: $0.executablePath, args: $0.arguments, workdir: $0.workingDirectory) }
            // Save migrated format
            saveCLIConfigs(configs)
            return configs
        }

        return []
    }

    /// Generate default config JSON text from presets.
    func defaultConfigJSON() -> String {
        let configs = PresetTargets.defaultCLIConfigs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(configs),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "[]"
    }

    var configFilePath: String {
        return configFileURL.path
    }

    // MARK: - CLI Session Persistence

    private func saveCLISessionSnapshots() {
        let snapshot = CLISessionPersistenceSnapshot(
            sessions: cliSessionManager.restorableSessions(),
            focusedSessionID: cliSessionManager.focusedSessionID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: cliSessionsFileURL, options: .atomic)
        }
    }

    private func saveGroupChatSnapshot() {
        let snapshot = GroupChatPersistenceSnapshot(
            activeGroupChatIDs: groupChatManager.groupChats.map(\.id),
            activeGroupChatID: groupChatManager.activeGroupChatID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: groupChatsFileURL, options: .atomic)
        }
    }

    private func restorePersistedCLISessions() {
        guard cliEnabled,
              let data = try? Data(contentsOf: cliSessionsFileURL) else {
            return
        }
        let decoder = JSONDecoder()

        if let snapshot = try? decoder.decode(CLISessionPersistenceSnapshot.self, from: data) {
            cliSessionManager.restoreSessions(from: snapshot.sessions, targets: targets)
            if let focusedID = snapshot.focusedSessionID,
               cliSessionManager.sessions.contains(where: { $0.id == focusedID }) {
                cliSessionManager.focusSession(focusedID)
            } else if let firstID = cliSessionManager.sessions.first?.id {
                cliSessionManager.focusSession(firstID)
            }
            return
        }

        // Backward compatibility with old schema that persisted only the session array.
        if let legacySessions = try? decoder.decode([CLISessionManager.RestorableSession].self, from: data) {
            cliSessionManager.restoreSessions(from: legacySessions, targets: targets)
            if let firstID = cliSessionManager.sessions.first?.id {
                cliSessionManager.focusSession(firstID)
            }
        }
    }

    private func restorePersistedGroupChats() {
        guard cliEnabled,
              let data = try? Data(contentsOf: groupChatsFileURL) else {
            return
        }
        let decoder = JSONDecoder()
        guard let snapshot = try? decoder.decode(GroupChatPersistenceSnapshot.self, from: data) else {
            return
        }

        for id in snapshot.activeGroupChatIDs {
            _ = groupChatManager.restoreClosedGroupChat(id, sessionManager: cliSessionManager)
        }

        if let activeID = snapshot.activeGroupChatID,
           groupChatManager.groupChats.contains(where: { $0.id == activeID }) {
            groupChatManager.focusGroupChat(activeID)
        }
    }
}

// MARK: - Supporting Types

enum ViewMode {
    case settings
    case cliSessions
    case groupChat
}

enum ElementPickerStep {
    case selectInput
    case selectOutput
}
