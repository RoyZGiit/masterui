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

    /// Active conversations per target.
    @Published var conversations: [UUID: Conversation] = [:]

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

    // MARK: - Private

    private let configFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui_config.json")
    }()

    private let connectorManager = ConnectorManager.shared

    // MARK: - Init

    private init() {
        // Load cliEnabled from UserDefaults (default true)
        self.cliEnabled = UserDefaults.standard.object(forKey: "cliEnabled") as? Bool ?? true

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

    // MARK: - Conversation

    func conversation(for targetID: UUID) -> Conversation {
        if let existing = conversations[targetID] {
            return existing
        }
        let conv = Conversation(targetID: targetID)
        conversations[targetID] = conv
        return conv
    }

    func currentConversation() -> Conversation? {
        guard let id = selectedTargetID else { return nil }
        return conversation(for: id)
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) async {
        guard let target = selectedTarget else { return }

        let conv = conversation(for: target.id)

        // Add user message
        let userMessage = Message(role: .user, content: text)
        await MainActor.run {
            conv.addMessage(userMessage)
        }

        // Add placeholder assistant message
        let assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        await MainActor.run {
            conv.addMessage(assistantMessage)
        }

        // Get connector and send
        let connector = connectorManager.connector(for: target)

        // Start monitoring for response
        connector.startMonitoring { [weak conv] responseText, isComplete in
            DispatchQueue.main.async {
                conv?.updateLastAssistantMessage(content: responseText, isStreaming: !isComplete)
                if isComplete {
                    connector.stopMonitoring()
                }
            }
        }

        // Inject text and trigger send
        let success = await connector.sendMessage(text)
        if !success {
            await MainActor.run {
                conv.updateLastAssistantMessage(
                    content: "Failed to send message. Make sure \(target.name) is running and MasterUI has accessibility permissions.",
                    isStreaming: false
                )
            }
            connector.stopMonitoring()
        }
    }

    // MARK: - Jump to App

    func jumpToApp() {
        guard let target = selectedTarget else { return }
        let connector = connectorManager.connector(for: target)
        connector.activateApp()
    }

    // MARK: - Persistence

    func saveCLIConfigs(_ configs: [CLIToolConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(configs) {
            try? data.write(to: configFileURL)
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
}

// MARK: - Supporting Types

enum ViewMode {
    case chat
    case settings
    case cliSessions
}

enum ElementPickerStep {
    case selectInput
    case selectOutput
}
