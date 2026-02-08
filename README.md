# MasterUI

**Universal AI Chat Aggregator for macOS**

MasterUI is a native macOS application that aggregates AI chat inputs from multiple apps into one unified floating panel. Instead of switching between ChatGPT, Claude, Cursor, DeepSeek, and other AI apps, you can send messages and view responses from a single interface.

## How It Works

MasterUI uses the macOS Accessibility API to interact with other running applications:

1. **Press `Cmd+Shift+Space`** to bring up the floating panel from anywhere
2. **Select a target AI app** (ChatGPT, Claude, Cursor, DeepSeek, etc.)
3. **Type your message** in the unified input bar
4. MasterUI automatically injects the text into the target app's input field and sends it
5. The AI's response is monitored and displayed back in the MasterUI panel
6. Click **"Jump to App"** when you need to see the full context (e.g., code changes in Cursor)

## Features

- **Floating Panel** — Always-on-top Spotlight-like interface, accessible via global hotkey
- **Multi-App Support** — Works with any macOS application that has accessible text input fields
- **CLI Tools Support** — Native support for interactive command-line AI tools (e.g., `claude`, `ollama`) via PTY
- **Pre-configured Targets** — Built-in support for ChatGPT, Claude, Cursor, DeepSeek, Kimi, and Doubao
- **Custom Targets** — Add any AI app (GUI) or CLI tool via Settings
- **Response Monitoring** — Dual-mode monitoring (AXObserver + polling) to capture AI responses including streaming
- **Auto-Recovery** — Smart detection and auto-recovery when target apps' accessibility interfaces become unresponsive
- **Element Picker** — Interactive tool to select input/output UI elements in any running application
- **Menu Bar App** — Runs as a lightweight menu bar application (no dock icon)
- **Conversation History** — Keeps track of your conversations per target app

## Requirements

- macOS 14 (Sonoma) or later
- **Accessibility Permission** — Required for interacting with other apps' UI elements

## Building

### Prerequisites

- Xcode 15+ or Swift 5.9+ toolchain

### Build from Command Line

```bash
swift build
```

### Run

```bash
swift run MasterUI
```

Or build and run from the `.build/debug/` directory:

```bash
swift build && .build/debug/MasterUI
```

### Open in Xcode

You can also open the project in Xcode:

```bash
open Package.swift
```

## Building the App Bundle

For proper macOS permissions handling, build the `.app` bundle:

```bash
bash scripts/bundle.sh
```

This creates `build/MasterUI.app` which can be added to Accessibility settings.

## First Launch

1. **Grant Accessibility Permission**:
   - Open **System Settings > Privacy & Security > Accessibility**
   - Click the **"+"** button
   - Navigate to the project's `build/` folder and add `MasterUI.app`
   - Alternatively, run `open build/MasterUI.app` and follow the system prompt

2. **Configure Targets**: The app comes with pre-configured targets for popular AI apps. Make sure the target apps are running.

3. **Pick Elements** (if needed): If the pre-configured element locators don't work for your version of an AI app, use **Settings > Pick Elements** to manually select the input field and output area.

## Pre-configured AI Targets

| App | Bundle ID | Status |
|-----|-----------|--------|
| ChatGPT | `com.openai.chat` | Pre-configured |
| Claude | `com.anthropic.claudefordesktop` | Pre-configured |
| Cursor | `com.todesktop.230313mzl4w4u92` | Pre-configured |
| DeepSeek | `com.deepseek.chat` | Pre-configured |
| Kimi | `cn.moonshot.kimi` | Pre-configured |
| Doubao | `com.bytedance.doubao.macos` | Pre-configured |

## Adding Custom Targets
 
MasterUI supports two types of custom targets: GUI Apps and CLI Tools.
 
### Adding a GUI App
1. Open **Settings** from the menu bar icon
2. Click **Add Target** (`+` button)
3. Choose **GUI App** tab
4. Enter the app's name and bundle ID
5. After adding, click **Pick Elements** to interactively select the input and output UI elements
 
### Adding a CLI Tool
1. Open **Settings**
2. Click **Add Target** (`+` button)
3. Choose **CLI Tool** tab
4. Enter the **Executable Path** (absolute path, e.g., `/opt/homebrew/bin/claude`)
5. (Optional) Enter arguments and working directory
6. Once added, MasterUI runs the tool in a background PTY and streams I/O directly to the chat interface
 
### Finding an App's Bundle ID

```bash
mdls -name kMDItemCFBundleIdentifier /Applications/YourApp.app
```

Or use Activity Monitor to find the process and its bundle identifier.

## Architecture

```
Sources/MasterUI/
├── App/                    # App entry, floating panel, hotkey
├── Models/                 # Data models (AITarget, Message, etc.)
├── Services/               # Core services (Accessibility, TextInjector, etc.)
├── Connectors/             # App-specific connectors
├── Views/                  # SwiftUI views
└── Utils/                  # Extensions and utilities
```

### Key Components

- **FloatingPanel** — NSPanel-based always-on-top window with vibrancy
- **AccessibilityService** — Core AXUIElement API wrapper for reading/writing to other apps
- **PTYManager** — Manages pseudo-terminals for running interactive CLI tools
- **ElementFinder** — Traverses accessibility trees to find specific UI elements
- **TextInjector** — Injects text into target apps (direct AXValue set + clipboard paste fallback)
- **ResponseMonitor** — Watches for AI responses via AXObserver notifications + polling
- **GenericConnector** — Combines injection and monitoring for any target app (with keyboard fallback)
- **CursorConnector** — Specialized connector for Cursor IDE with advanced AX tree health checking and auto-recovery
- **CLIConnector** — Connects to PTYManager to stream stdin/stdout for command-line tools

### Diagnostics

MasterUI includes a diagnostic mode to inspect any app's accessibility tree:

```bash
# Show all text inputs and a shallow tree dump
build/MasterUI.app/Contents/MacOS/MasterUI --diagnose com.todesktop.230313mzl4w4u92

# Show only text input elements
build/MasterUI.app/Contents/MacOS/MasterUI --diagnose <bundleID> --inputs

# Show full accessibility tree (depth=6)
build/MasterUI.app/Contents/MacOS/MasterUI --diagnose <bundleID> --tree
```

### Technical Notes on Electron Apps
 
Electron-based apps (Cursor, VS Code, etc.) expose their UI as deeply nested `AXGroup` and `AXStaticText` elements within an `AXWebArea`. Standard `AXTextArea` elements are typically **not** present for chat inputs.
 
**Cursor Integration Strategy:**
1. **Locating Chat**: Tries to find chat bubbles via specific AXDOMIdentifiers. If that fails (e.g. UI update), falls back to a heuristic search of text siblings near the input field.
2. **Sending**: Uses a robust keyboard sequence: Activate -> Wait -> Cmd+L (Focus) -> Cmd+V (Paste) -> Enter.
3. **Health Check**: Automatically detects if Cursor's Accessibility API is unresponsive (common Electron issue). If detected, MasterUI switches to "Blind Mode" (sends without reading) and polls in the background to auto-recover once Cursor is restarted.

## Troubleshooting

### "Failed to send message"
- Ensure the target app is running
- Check that MasterUI has Accessibility permission
- Try re-picking the input element via Settings > Pick Elements

### Responses not showing
- The output locator may need to be reconfigured after an app update
- Use Settings > Pick Elements to re-select the output area
- Check the console (Settings > Dump AX Tree) to inspect the app's accessibility structure

### Global hotkey not working
- Ensure no other app is using Cmd+Shift+Space
- Check that MasterUI is running (look for the icon in the menu bar)

## License

MIT
