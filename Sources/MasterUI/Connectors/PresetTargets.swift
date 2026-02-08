import Foundation

// MARK: - PresetTargets

/// Pre-configured AI target applications with known accessibility paths.
/// These can be used as starting points and customized by the user.
struct PresetTargets {
    /// All available preset configurations.
    static let all: [AITarget] = [
        chatGPT,
        claude,
        cursor,
        deepSeek,
        kimi,
        doubao,
        claudeCode,
    ]

    // MARK: - ChatGPT (macOS App)

    static let chatGPT = AITarget(
        name: "ChatGPT",
        bundleID: "com.openai.chat",
        iconSymbol: "brain.head.profile",
        colorHex: "#10A37F",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )

    // MARK: - Claude (macOS App)

    static let claude = AITarget(
        name: "Claude",
        bundleID: "com.anthropic.claudefordesktop",
        iconSymbol: "sparkles",
        colorHex: "#D97757",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )

    // MARK: - Cursor IDE

    static let cursor = AITarget(
        name: "Cursor",
        bundleID: "com.todesktop.230313mzl4w4u92",
        iconSymbol: "cursorarrow.click.2",
        colorHex: "#7C3AED",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )

    // MARK: - DeepSeek (macOS App)

    static let deepSeek = AITarget(
        name: "DeepSeek",
        bundleID: "com.deepseek.chat",
        iconSymbol: "magnifyingglass.circle.fill",
        colorHex: "#4D6BFE",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )

    // MARK: - Kimi (Moonshot)

    static let kimi = AITarget(
        name: "Kimi",
        bundleID: "cn.moonshot.kimi",
        iconSymbol: "moon.fill",
        colorHex: "#5B6EF5",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )

    // MARK: - Claude Code (CLI)

    static let claudeCode = AITarget(
        name: "Claude Code",
        type: .cliTool,
        executablePath: detectClaudePath(),
        arguments: [],
        workingDirectory: nil,
        iconSymbol: "terminal.fill",
        colorHex: "#D97757"
    )

    /// Detect the installed `claude` CLI path.
    private static func detectClaudePath() -> String {
        let candidates = [
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Default fallback
        return "/usr/local/bin/claude"
    }

    // MARK: - Doubao (字节跳动)

    static let doubao = AITarget(
        name: "豆包",
        bundleID: "com.bytedance.doubao.macos",
        iconSymbol: "flame.fill",
        colorHex: "#FF6B35",
        inputLocator: ElementLocator(
            role: "AXTextArea",
            deepSearch: true
        ),
        outputLocator: ElementLocator(
            role: "AXGroup",
            deepSearch: true
        ),
        sendMethod: .enterKey
    )
}
