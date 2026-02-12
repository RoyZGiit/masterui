import SwiftUI

// MARK: - GroupChatInputBar

/// Text input bar for sending messages to the group chat.
/// Always enabled — the user can send messages at any time, even while AIs are responding.
struct GroupChatInputBar: View {
    @ObservedObject var coordinator: GroupChatCoordinator
    let isWaiting: Bool

    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Message all participants...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit {
                    send()
                }

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(canSend ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            isFocused = true
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        coordinator.sendUserMessage(text)
    }
}
