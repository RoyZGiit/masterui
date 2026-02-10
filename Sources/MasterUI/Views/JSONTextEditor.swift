import SwiftUI
import AppKit

/// AppKit-backed editor for reliable macOS editing shortcuts and plain-text behavior.
struct JSONTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (() -> Void)?
    var onTextDidEndEditing: (() -> Void)?
    var onSaveCommand: (() -> Void)?
    var onFormatCommand: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = ShortcutTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true

        // Disable automatic substitutions that mutate JSON input.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        textView.onSaveCommand = onSaveCommand
        textView.onFormatCommand = onFormatCommand

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ShortcutTextView else { return }
        textView.onSaveCommand = onSaveCommand
        textView.onFormatCommand = onFormatCommand

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextEditor

        init(parent: JSONTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onTextDidEndEditing?()
        }
    }
}

final class ShortcutTextView: NSTextView {
    var onSaveCommand: (() -> Void)?
    var onFormatCommand: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if flags == [.command], key == "s" {
            onSaveCommand?()
            return true
        }
        if flags == [.command, .shift], key == "f" {
            onFormatCommand?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
