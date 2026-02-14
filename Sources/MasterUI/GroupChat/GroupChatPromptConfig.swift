import Foundation

// MARK: - GroupChatPromptConfig

/// Manages the group chat prompt configuration stored at ~/.masterui/groupchat_prompt.json.
///
/// JSON structure:
/// ```json
/// {
///   "prompt_template": "...",
///   "pass_keyword": "[PASS]"
/// }
/// ```
///
/// Supported placeholders in prompt_template:
///   {{MY_NAME}}            – this participant's display name
///   {{PARTICIPANTS}}       – comma-separated list of other participants
///   {{HISTORY_PATH}}       – absolute path to the history JSON file
///   {{NEW_MESSAGE_COUNT}}  – number of new messages since last turn
final class GroupChatPromptConfig: ObservableObject {

    static let shared = GroupChatPromptConfig()

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".masterui/groupchat_prompt.json").path
    }()

    @Published var promptTemplate: String
    @Published var passKeyword: String

    static let defaultPromptTemplate = """
    [Group Chat] You are "{{MY_NAME}}", participants: {{PARTICIPANTS}}. History: {{HISTORY_PATH}}
    Do not ask for pasted messages. Use the history file as the only source of latest conversation updates.
    If you have nothing to add, reply with exactly "[PASS]".
    Use @xxx in the message means this message is just for xxx,reply with exactly "[PASS]" if xxx is not you.
    If you know what to do, there is no need to reply anything, just do it.
    """

    static let defaultPassKeyword = "[PASS]"

    private init() {
        let loaded = Self.loadFromDisk()
        self.promptTemplate = loaded.promptTemplate
        self.passKeyword = loaded.passKeyword
    }

    /// Renders the template with the given values.
    func render(
        myName: String,
        participants: String,
        historyPath: String,
        newMessageCount: Int
    ) -> String {
        promptTemplate
            .replacingOccurrences(of: "{{MY_NAME}}", with: myName)
            .replacingOccurrences(of: "{{PARTICIPANTS}}", with: participants)
            .replacingOccurrences(of: "{{HISTORY_PATH}}", with: historyPath)
            .replacingOccurrences(of: "{{NEW_MESSAGE_COUNT}}", with: String(newMessageCount))
    }

    func save() {
        let data = ConfigData(
            prompt_template: promptTemplate,
            pass_keyword: passKeyword
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let json = try? encoder.encode(data) else { return }

        let dir = (Self.configPath as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try? json.write(to: URL(fileURLWithPath: Self.configPath), options: .atomic)
    }

    func resetToDefaults() {
        promptTemplate = Self.defaultPromptTemplate
        passKeyword = Self.defaultPassKeyword
        save()
    }

    func reload() {
        let loaded = Self.loadFromDisk()
        promptTemplate = loaded.promptTemplate
        passKeyword = loaded.passKeyword
    }

    // MARK: - Private

    private struct ConfigData: Codable {
        var prompt_template: String
        var pass_keyword: String
    }

    private static func loadFromDisk() -> (promptTemplate: String, passKeyword: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(ConfigData.self, from: data)
        else {
            // Write default config
            let defaultConfig = ConfigData(
                prompt_template: defaultPromptTemplate,
                pass_keyword: defaultPassKeyword
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let json = try? encoder.encode(defaultConfig) {
                let dir = (configPath as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: dir) {
                    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                }
                try? json.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            }
            return (defaultPromptTemplate, defaultPassKeyword)
        }
        return (config.prompt_template, config.pass_keyword)
    }
}
