import Foundation

// MARK: - PresetTargets

/// Pre-configured AI target applications with known accessibility paths.
/// These can be used as starting points and customized by the user.
struct PresetTargets {
    /// All available preset configurations.
    static let all: [AITarget] = [
        claudeCode,
        gitHubCopilot,
        ollama,
        chatGPTCLI,
        gemini,
        openCode,
        codex,
    ]

    // MARK: - Claude Code (CLI)

    static let claudeCode = AITarget(
        name: "Claude Code",
        type: .cliTool,
        executablePath: detectPath(names: ["claude"]),
        arguments: [],
        iconSymbol: "sparkles",
        colorHex: "#D97757",
        installationGuide: "npm install -g @anthropic-ai/claude-code"
    )

    // MARK: - GitHub Copilot CLI

    static let gitHubCopilot = AITarget(
        name: "GitHub Copilot",
        type: .cliTool,
        executablePath: detectPath(names: ["gh"]),
        arguments: ["copilot", "repl"],
        iconSymbol: "hammer.fill",
        colorHex: "#24292F",
        installationGuide: "brew install gh && gh extension install github/gh-copilot"
    )

    // MARK: - Ollama

    static let ollama = AITarget(
        name: "Ollama",
        type: .cliTool,
        executablePath: detectPath(names: ["ollama"]),
        arguments: ["run", "llama3"],
        iconSymbol: "laptopcomputer",
        colorHex: "#FFFFFF",
        installationGuide: "brew install ollama (or visit ollama.com)"
    )

    // MARK: - ChatGPT (Python CLI)

    static let chatGPTCLI = AITarget(
        name: "ChatGPT CLI",
        type: .cliTool,
        executablePath: detectPath(names: ["chatgpt-cli", "chatgpt"]),
        arguments: [],
        iconSymbol: "brain",
        colorHex: "#74AA9C",
        installationGuide: "pip install chatgpt-cli-tool"
    )

    // MARK: - Gemini CLI

    static let gemini = AITarget(
        name: "Gemini",
        type: .cliTool,
        executablePath: detectPath(names: ["gemini"]),
        arguments: [],
        iconSymbol: "sparkles.rectangle.stack.fill",
        colorHex: "#4E8CF7",
        installationGuide: "npm install -g @google/gemini-cli"
    )

    // MARK: - OpenCode (Z.AI)

    static let openCode = AITarget(
        name: "OpenCode",
        type: .cliTool,
        executablePath: detectPath(names: ["opencode"]),
        arguments: [],
        iconSymbol: "chevron.left.forwardslash.chevron.right",
        colorHex: "#FF4F00",
        installationGuide: "npm install -g opencode-ai"
    )

    // MARK: - OpenAI Codex

    static let codex = AITarget(
        name: "Codex",
        type: .cliTool,
        executablePath: detectPath(names: ["codex"]),
        arguments: [],
        iconSymbol: "curlybraces",
        colorHex: "#10A37F",
        installationGuide: "npm install -g @openai/codex"
    )

    // MARK: - CLIToolConfig Helpers

    /// Default CLI tool configurations for the JSON editor.
    static func defaultCLIConfigs() -> [CLIToolConfig] {
        return [
            CLIToolConfig(name: "Claude Code",    path: "/usr/bin/claude",   args: []),
            CLIToolConfig(name: "GitHub Copilot", path: "/usr/bin/gh",       args: ["copilot", "repl"]),
            CLIToolConfig(name: "Ollama",         path: "/usr/bin/ollama",   args: ["run", "llama3"]),
            CLIToolConfig(name: "ChatGPT CLI",    path: "/usr/bin/chatgpt",  args: []),
            CLIToolConfig(name: "Gemini",         path: "/usr/bin/gemini",   args: []),
            CLIToolConfig(name: "OpenCode",       path: "/usr/bin/opencode", args: []),
            CLIToolConfig(name: "Codex",          path: "/usr/bin/codex",    args: []),
        ]
    }

    /// Lookup UI metadata (icon, color, installationGuide) by tool name.
    static func metadata(for name: String) -> (icon: String, color: String, installGuide: String?)? {
        guard let preset = all.first(where: { $0.name == name }) else { return nil }
        return (icon: preset.iconSymbol, color: preset.colorHex, installGuide: preset.installationGuide)
    }

    // MARK: - Helper

    /// Detect the installed CLI path by searching directories in the user's
    /// real shell PATH (captured via `ShellEnvironment`).
    static func detectPath(names: [String]) -> String {
        let pathDirs = (ShellEnvironment.resolved["PATH"] ?? "")
            .components(separatedBy: ":")
            .filter { !$0.isEmpty }

        for name in names {
            for dir in pathDirs {
                let fullPath = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        return names.first ?? ""
    }
}
