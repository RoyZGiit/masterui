import Foundation
import SwiftUI

// MARK: - AppState

/// Global application state, managing targets, conversations, and settings.
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published State

    /// All configured AI targets.
    @Published var targets: [AITarget] = []

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

    private let userDefaultsKey = "masterui_targets"
    private let connectorManager = ConnectorManager.shared

    // MARK: - Init

    private init() {
        loadTargets()
        if targets.isEmpty {
            // Load presets on first launch
            targets = PresetTargets.all
            saveTargets()
        } else {
            // Merge any new presets that were added since last launch
            mergeNewPresets()
        }
        // Select first enabled target
        selectedTargetID = targets.first(where: { $0.isEnabled })?.id
    }

    /// Add any preset targets that don't exist yet (by name match).
    private func mergeNewPresets() {
        let existingNames = Set(targets.map { $0.name })
        var added = false
        for preset in PresetTargets.all {
            if !existingNames.contains(preset.name) {
                targets.append(preset)
                added = true
            }
        }
        if added {
            saveTargets()
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

    func addTarget(_ target: AITarget) {
        targets.append(target)
        saveTargets()
    }

    func removeTarget(id: UUID) {
        targets.removeAll { $0.id == id }
        conversations.removeValue(forKey: id)
        connectorManager.removeConnector(for: id)
        if selectedTargetID == id {
            selectedTargetID = enabledTargets.first?.id
        }
        saveTargets()
    }

    func updateTarget(_ target: AITarget) {
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
            saveTargets()
        }
    }

    func selectTarget(_ id: UUID) {
        selectedTargetID = id
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
                    content: "⚠️ Failed to send message. Make sure \(target.name) is running and MasterUI has accessibility permissions.",
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

    private func saveTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadTargets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([AITarget].self, from: data) else {
            return
        }
        targets = decoded
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
