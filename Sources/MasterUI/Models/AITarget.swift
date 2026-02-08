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
        sendMethod: SendMethod = .enterKey
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
    }
}

// MARK: - SendMethod

/// How to trigger "send" after injecting text into the input field.
enum SendMethod: String, Codable, CaseIterable {
    case enterKey = "enter"         // Simulate pressing Enter
    case cmdEnterKey = "cmd_enter"  // Simulate pressing Cmd+Enter
    case clickSend = "click_send"   // Click a send button via AX action
}
