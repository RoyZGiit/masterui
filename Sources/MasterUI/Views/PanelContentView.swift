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
            if appState.viewMode == .settings {
                SettingsView()
            } else {
                HSplitView {
                    // Left: Unified Sidebar
                    SessionSidebarView(
                        onRename: { sessionID, title in
                            appState.cliSessionManager.renameSession(sessionID, title: title)
                        },
                        onReload: { sessionID in
                            appState.cliSessionManager.reloadSession(sessionID)
                        },
                        onSelectClosedSession: { closed in
                            // This state might need to be shared or handled
                            // For now, we can pass it to CLILayoutView or handle it here
                            NotificationCenter.default.post(name: .selectClosedSession, object: closed)
                        }
                    )
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

                    // Right: Main Area
                    Group {
                        if appState.viewMode == .groupChat {
                            GroupChatMainArea(
                                manager: appState.groupChatManager,
                                sessionManager: appState.cliSessionManager
                            )
                        } else {
                            CLIMainArea(sessionManager: appState.cliSessionManager)
                        }
                    }
                }
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
