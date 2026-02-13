import SwiftUI
import AppKit

// MARK: - GroupChatInputBar

/// Text input bar for sending messages to the group chat.
/// Always enabled — the user can send messages at any time, even while AIs are responding.
struct GroupChatInputBar: View {
    @ObservedObject var coordinator: GroupChatCoordinator
    let isWaiting: Bool

    @State private var inputText = ""
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Message group...")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 10)
                    }

                    GroupChatTextEditor(
                        text: $inputText,
                        isFocused: $isFocused,
                        onSubmit: send
                    )
                    .frame(minHeight: 30, maxHeight: 110)
                }
                .padding(.vertical, 2)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                        .symbolEffect(.bounce, value: canSend)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
        }

        coordinator.sendUserMessage(text)
    }
}

private struct GroupChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = GroupChatShortcutTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.string = text
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GroupChatShortcutTextView else { return }
        textView.onSubmit = onSubmit

        if textView.string != text {
            textView.string = text
        }

        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class GroupChatShortcutTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)

        if isReturn && (hasShift || hasCommand) {
            insertNewline(nil)
            return
        }

        if isReturn {
            // IME composition should be committed first, not sent as a message.
            if !hasMarkedText() {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
            return
        }

        super.keyDown(with: event)
    }
}
