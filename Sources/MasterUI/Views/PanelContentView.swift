import SwiftUI

// MARK: - PanelContentView

/// The main content view displayed inside the floating panel.
struct PanelContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header with target selector
            headerBar

            Divider()

            // Main Content Area
            switch appState.viewMode {
            case .settings:
                SettingsView()
            case .chat:
                // Conversation area
                if let targetID = appState.selectedTargetID {
                    ConversationView(conversation: appState.conversation(for: targetID))
                } else {
                    emptyState
                }
            case .cliSessions:
                CLILayoutView(sessionManager: appState.cliSessionManager)
            }

            // Input bar (only visible in chat mode)
            if appState.viewMode == .chat {
                Divider()
                InputBarView()
            }
        }
        .frame(minWidth: appState.viewMode == .cliSessions ? 700 : 480,
               minHeight: appState.viewMode == .cliSessions ? 500 : 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .onTapGesture {
                    appState.viewMode = .chat
                }

            Text("MasterUI")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            // Mode toggle: Chat / Terminal
            modeToggle

            Spacer()

            if appState.viewMode == .chat {
                // Target picker
                TargetPickerView()

                // Jump to app button
                if let target = appState.selectedTarget {
                    Button(action: { appState.jumpToApp() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                            Text("Jump to \(target.name)")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Switch to \(target.name) app")
                }

                // Status indicator
                statusIndicator
            }

            // Settings Toggle (not shown in CLI mode since CLI has its own toolbar)
            if appState.viewMode != .cliSessions {
                Button(action: {
                    withAnimation(.snappy) {
                        if appState.viewMode == .settings {
                            appState.viewMode = .chat
                        } else {
                            appState.viewMode = .settings
                        }
                    }
                }) {
                    Image(systemName: appState.viewMode == .settings ? "xmark.circle.fill" : "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(appState.viewMode == .settings ? "Close Settings" : "Open Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeButton(icon: "bubble.left.fill", mode: .chat, label: "Chat")
            modeButton(icon: "terminal.fill", mode: .cliSessions, label: "Terminal")
        }
        .padding(2)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func modeButton(icon: String, mode: ViewMode, label: String) -> some View {
        Button(action: {
            withAnimation(.snappy) {
                appState.viewMode = mode
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(appState.viewMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.viewMode == mode ? .primary : .secondary)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Group {
            if let target = appState.selectedTarget {
                let isRunning = AccessibilityService.shared.isAppRunning(bundleID: target.bundleID)
                Circle()
                    .fill(isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .help(isRunning ? "\(target.name) is running" : "\(target.name) is not running")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No AI Target Selected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Select an AI application from the dropdown above,\nor add a new target in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
