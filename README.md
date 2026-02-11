# MasterUI

A macOS menu bar app that puts all your AI coding CLIs in one floating panel.

Press `Cmd+Shift+Space` to open a Spotlight-style terminal window. Pick a tool — Claude Code, Gemini, Copilot, Ollama, Codex, or anything else — and start working. Each tool runs in its own PTY-backed terminal with full color, scrollback, and keyboard support, powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
<img width="3840" height="1970" alt="1" src="https://github.com/user-attachments/assets/163b49e4-3a1b-49d0-bc50-c6dfe36c7c49" />
<img width="3840" height="1970" alt="2" src="https://github.com/user-attachments/assets/5d8bce81-1d2d-4241-a37e-655733592886" />

## ClI

- **Global Hotkey** — `Cmd+Shift+Space` to toggle the floating panel from anywhere
- **Side-by-Side Sessions** — Run multiple CLI tools simultaneously with a sidebar for switching
- **Real Terminal** — Full PTY emulation: colors, cursor movement, interactive prompts all work
- **JSON Config** — Add any CLI tool by editing a simple JSON file in Settings
- **Auto-Detect** — Built-in presets for popular tools, auto-detected from common install paths
- **Lightweight** — Menu bar only, no dock icon

## Built-in Presets

| Tool | Install |
|------|---------|
| Claude Code | `npm install -g @anthropic-ai/claude-code` |
| GitHub Copilot | `brew install gh && gh extension install github/gh-copilot` |
| Gemini CLI | `npm install -g @google/gemini-cli` |
| Ollama | `brew install ollama` |
| Codex | `npm install -g @openai/codex` |
| OpenCode | `npm install -g opencode-ai` |
| ChatGPT CLI | `pip install chatgpt-cli-tool` |

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+

## Build & Run

```bash
swift build && swift run MasterUI
```

Or build the `.app` bundle for proper Accessibility permissions:

```bash
bash scripts/bundle.sh
open build/MasterUI.app
```

Grant Accessibility permission on first launch: **System Settings > Privacy & Security > Accessibility**.

## Configuration

Open Settings from the menu bar icon. Tools are configured as JSON:

```json
[
  {
    "name": "Claude Code",
    "path": "/usr/bin/claude",
    "args": [],
    "workdir": null
  }
]
```

Each entry needs `name` and `path`. `args` and `workdir` are optional.

## License

MIT
