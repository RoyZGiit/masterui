import SwiftUI
import AppKit

// MARK: - GroupChatInputBar

struct GroupChatInputBar: View {
    @ObservedObject var coordinator: GroupChatCoordinator
    let isWaiting: Bool
    var participantNames: [String] = []
    var insertMentionPublisher = MentionInsertPublisher()

    @State private var inputText = ""
    @State private var isFocused = false
    @State private var showMentionPopover = false
    @State private var mentionQuery = ""
    @State private var selectedMentionIndex = 0

    private var filteredMentions: [String] {
        let q = mentionQuery.lowercased()
        if q.isEmpty { return participantNames }
        return participantNames.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMentionPopover && !filteredMentions.isEmpty {
                mentionList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
                            onSubmit: send,
                            onMoveMentionSelection: moveMentionSelection,
                            onConfirmMentionSelection: confirmMentionSelection
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
        }
        .onAppear { isFocused = true }
        .onChange(of: inputText) { updateMentionState() }
        .onReceive(insertMentionPublisher.$pendingName) { name in
            guard let name, !name.isEmpty else { return }
            insertMention(name)
            insertMentionPublisher.pendingName = nil
        }
    }

    // MARK: - Mention list

    private var mentionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredMentions, id: \.self) { name in
                    let isSelected = selectedMentionName == name
                    Button { completeMention(name) } label: {
                        HStack(spacing: 8) {
                            Text("@")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text(name)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, y: -2)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Logic

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedMentionName: String? {
        guard !filteredMentions.isEmpty else { return nil }
        let safeIndex = max(0, min(selectedMentionIndex, filteredMentions.count - 1))
        return filteredMentions[safeIndex]
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        showMentionPopover = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { inputText = "" }
        coordinator.sendUserMessage(text)
    }

    private func updateMentionState() {
        guard let range = activeMentionRange() else {
            if showMentionPopover {
                withAnimation(.easeOut(duration: 0.1)) { showMentionPopover = false }
            }
            selectedMentionIndex = 0
            return
        }
        mentionQuery = String(inputText[range])
        if filteredMentions.isEmpty {
            selectedMentionIndex = 0
        } else {
            selectedMentionIndex = min(selectedMentionIndex, filteredMentions.count - 1)
        }
        if !showMentionPopover {
            selectedMentionIndex = 0
            withAnimation(.easeOut(duration: 0.1)) { showMentionPopover = true }
        }
    }

    private func activeMentionRange() -> Range<String.Index>? {
        guard let atIndex = inputText.lastIndex(of: "@") else { return nil }
        if atIndex != inputText.startIndex {
            let before = inputText.index(before: atIndex)
            if !inputText[before].isWhitespace && !inputText[before].isNewline { return nil }
        }
        let afterAt = inputText.index(after: atIndex)
        if afterAt >= inputText.endIndex { return afterAt..<inputText.endIndex }
        let query = inputText[afterAt...]
        if query.contains(" ") || query.contains("\n") { return nil }
        return afterAt..<inputText.endIndex
    }

    private func completeMention(_ name: String) {
        guard let atIndex = inputText.lastIndex(of: "@") else { return }
        inputText = String(inputText[..<atIndex]) + "@\(name) "
        selectedMentionIndex = 0
        withAnimation(.easeOut(duration: 0.1)) { showMentionPopover = false }
    }

    private func insertMention(_ name: String) {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            inputText = "@\(name) "
        } else {
            inputText = trimmed + " @\(name) "
        }
    }

    private func moveMentionSelection(_ delta: Int) -> Bool {
        guard showMentionPopover, !filteredMentions.isEmpty else { return false }
        let count = filteredMentions.count
        selectedMentionIndex = (selectedMentionIndex + delta + count) % count
        return true
    }

    private func confirmMentionSelection() -> Bool {
        guard showMentionPopover, let name = selectedMentionName else { return false }
        completeMention(name)
        return true
    }
}

// MARK: - MentionInsertPublisher

final class MentionInsertPublisher: ObservableObject {
    @Published var pendingName: String?
}

// MARK: - GroupChatTextEditor

private struct GroupChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onMoveMentionSelection: (Int) -> Bool
    let onConfirmMentionSelection: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

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
        textView.onMoveMentionSelection = onMoveMentionSelection
        textView.onConfirmMentionSelection = onConfirmMentionSelection
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
        textView.onMoveMentionSelection = onMoveMentionSelection
        textView.onConfirmMentionSelection = onConfirmMentionSelection
        if textView.string != text { textView.string = text }
        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { self._text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class GroupChatShortcutTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMoveMentionSelection: ((Int) -> Bool)?
    var onConfirmMentionSelection: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let hasModifiers = !event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty
        if !hasModifiers {
            if event.keyCode == 126, onMoveMentionSelection?(-1) == true { return } // Up
            if event.keyCode == 125, onMoveMentionSelection?(1) == true { return } // Down
        }

        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)

        if isReturn && (hasShift || hasCommand) {
            insertNewline(nil)
            return
        }
        if isReturn {
            if onConfirmMentionSelection?() == true { return }
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
