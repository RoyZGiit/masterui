import SwiftUI

// MARK: - InputBarView

/// The input bar at the bottom of the panel for typing messages.
struct InputBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                // Text input
                TextEditor(text: $inputText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .frame(minHeight: 36, maxHeight: 120)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                // Send button
                Button(action: sendMessage) {
                    Group {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                .disabled(!canSend)
                .help("Send message (Enter)")
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Target name hint
            if let target = appState.selectedTarget {
                HStack {
                    Text("Sending to")
                        .foregroundStyle(.tertiary)
                    Text(target.name)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    let isRunning = AccessibilityService.shared.isAppRunning(bundleID: target.bundleID)
                    if !isRunning {
                        Text("(not running)")
                            .foregroundStyle(.red.opacity(0.7))
                    }

                    Spacer()

                    if !PermissionsManager.shared.hasAccessibilityPermission {
                        Button("Grant Access") {
                            PermissionsManager.shared.openAccessibilitySettings()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isSending
        && appState.selectedTarget != nil
    }

    private func sendMessage() {
        guard canSend else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        isSending = true

        Task {
            await appState.sendMessage(text)
            await MainActor.run {
                isSending = false
            }
        }
    }
}
