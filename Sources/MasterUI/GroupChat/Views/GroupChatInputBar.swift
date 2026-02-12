import SwiftUI

// MARK: - GroupChatInputBar

/// Text input bar for sending messages to the group chat.
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
                .disabled(isWaiting)

            if isWaiting {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
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
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWaiting
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting else { return }
        inputText = ""
        coordinator.sendUserMessage(text)
    }
}
