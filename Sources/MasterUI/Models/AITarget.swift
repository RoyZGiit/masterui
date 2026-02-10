import Foundation

// MARK: - TargetType

enum TargetType: String, Codable {
    case guiApp
    case cliTool
}

// MARK: - AITarget

/// Represents a target AI application that MasterUI can interact with.
struct AITarget: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: TargetType
    
    // GUI specific
    var bundleID: String
    
    // CLI specific
    var executablePath: String
    var arguments: [String]
    var workingDirectory: String?
    
    var iconSymbol: String          // SF Symbol name for display
    var colorHex: String            // Accent color hex for the target
    var inputLocator: ElementLocator
    var outputLocator: ElementLocator
    var isEnabled: Bool
    var sendMethod: SendMethod
    var installationGuide: String? // Help text/command to install if missing

    // Custom coding keys to simplify JSON output
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case executablePath, arguments, workingDirectory
        // Optional/Internal fields included but can be omitted in minimal config if default
        case bundleID, iconSymbol, colorHex, inputLocator, outputLocator, isEnabled, sendMethod, installationGuide
    }
    
    // We only want to encode essential CLI fields when it's a CLI tool to keep JSON clean,
    // but Codable doesn't support conditional encoding easily without manual implementation.
    // However, the user asked for "only path, arguments and workdir". 
    // We will stick to standard encoding but users can manually simplify the JSON if they want, 
    // provided they keep required fields.
    
    // For the purpose of the "Config Editor", we are showing the full JSON.
    // If the user meant "In the UI editor, only show these fields for CLI tools", we handled that in SettingsView.
    // If the user meant "The JSON file should ONLY contain these fields", that would break decoding of other properties.
    // Assuming the user wants a SIMPLIFIED JSON representation.
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        
        if type == .cliTool {
            try container.encode(executablePath, forKey: .executablePath)
            try container.encode(arguments, forKey: .arguments)
            try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        } else {
            try container.encode(bundleID, forKey: .bundleID)
            try container.encode(inputLocator, forKey: .inputLocator)
            try container.encode(outputLocator, forKey: .outputLocator)
            try container.encode(iconSymbol, forKey: .iconSymbol)
            try container.encode(colorHex, forKey: .colorHex)
            try container.encode(isEnabled, forKey: .isEnabled)
            try container.encode(sendMethod, forKey: .sendMethod)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(TargetType.self, forKey: .type)
        
        // Default values for missing fields
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "bubble.left.fill"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#007AFF"
        inputLocator = try container.decodeIfPresent(ElementLocator.self, forKey: .inputLocator) ?? ElementLocator()
        outputLocator = try container.decodeIfPresent(ElementLocator.self, forKey: .outputLocator) ?? ElementLocator()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sendMethod = try container.decodeIfPresent(SendMethod.self, forKey: .sendMethod) ?? .enterKey
        installationGuide = try container.decodeIfPresent(String.self, forKey: .installationGuide)
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: TargetType = .guiApp,
        bundleID: String = "",
        executablePath: String = "",
        arguments: [String] = [],
        workingDirectory: String? = nil,
        iconSymbol: String = "bubble.left.fill",
        colorHex: String = "#007AFF",
        inputLocator: ElementLocator = ElementLocator(),
        outputLocator: ElementLocator = ElementLocator(),
        isEnabled: Bool = true,
        sendMethod: SendMethod = .enterKey,
        installationGuide: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.inputLocator = inputLocator
        self.outputLocator = outputLocator
        self.isEnabled = isEnabled
        self.sendMethod = sendMethod
        self.installationGuide = installationGuide
    }
}

// MARK: - SendMethod

/// How to trigger "send" after injecting text into the input field.
enum SendMethod: String, Codable, CaseIterable {
    case enterKey = "enter"         // Simulate pressing Enter
    case cmdEnterKey = "cmd_enter"  // Simulate pressing Cmd+Enter
    case clickSend = "click_send"   // Click a send button via AX action
}
