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
            case .cliSessions:
                CLILayoutView(sessionManager: appState.cliSessionManager)
            case .groupChat:
                GroupChatLayoutView(
                    manager: appState.groupChatManager,
                    sessionManager: appState.cliSessionManager
                )
            }
        }
        .frame(minWidth: appState.viewMode == .settings ? 480 : 700,
               minHeight: appState.viewMode == .settings ? 400 : 500)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("MasterUI")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Group Chat Toggle
            Button(action: {
                withAnimation(.snappy) {
                    if appState.viewMode == .groupChat {
                        appState.viewMode = .cliSessions
                    } else {
                        appState.viewMode = .groupChat
                    }
                }
            }) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(appState.viewMode == .groupChat ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.viewMode == .groupChat ? "Back to Sessions" : "Group Chat")

            // Settings Toggle
            Button(action: {
                withAnimation(.snappy) {
                    if appState.viewMode == .settings {
                        appState.viewMode = .cliSessions
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NotificationCenter.default.post(name: .togglePanelMaximize, object: nil)
        }
    }

}
