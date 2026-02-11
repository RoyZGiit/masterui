import SwiftUI
import AppKit

/// AppKit-backed editor with JSON highlighting and Sublime-inspired visuals.
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
        let theme = JSONEditorTheme.sublimeLike
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.editorBackground

        let textView = ShortcutTextView()
        textView.delegate = context.coordinator
        textView.editorTheme = theme
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.backgroundColor = theme.editorBackground
        textView.textColor = theme.foreground
        textView.insertionPointColor = theme.foreground
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selectionBackground,
            .foregroundColor: theme.foreground
        ]

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
        textView.typingAttributes = JSONSyntaxHighlighter.baseAttributes(for: theme, font: textView.font!)

        textView.onSaveCommand = onSaveCommand
        textView.onFormatCommand = onFormatCommand

        scrollView.documentView = textView
        let lineNumberRuler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.applyHighlight(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ShortcutTextView else { return }
        textView.onSaveCommand = onSaveCommand
        textView.onFormatCommand = onFormatCommand

        if textView.string != text {
            let currentSelection = textView.selectedRange()
            textView.string = text
            let boundedLocation = min(currentSelection.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: boundedLocation, length: 0))
            context.coordinator.applyHighlight(to: textView)
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
            if let shortcutTextView = textView as? ShortcutTextView {
                applyHighlight(to: shortcutTextView)
            }
            parent.onTextChange?()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onTextDidEndEditing?()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? ShortcutTextView else { return }
            textView.needsDisplay = true
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func applyHighlight(to textView: ShortcutTextView) {
            guard let font = textView.font else { return }
            JSONSyntaxHighlighter.highlight(textView: textView, font: font, theme: textView.editorTheme)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

final class ShortcutTextView: NSTextView {
    var onSaveCommand: (() -> Void)?
    var onFormatCommand: (() -> Void)?
    fileprivate var editorTheme: JSONEditorTheme = .sublimeLike

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard selectedRange().location != NSNotFound else { return }
        guard let layoutManager = layoutManager else { return }

        let selectedLineRange = (string as NSString).lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let selectedGlyphRange = layoutManager.glyphRange(forCharacterRange: selectedLineRange, actualCharacterRange: nil)
        let origin = textContainerOrigin

        layoutManager.enumerateLineFragments(forGlyphRange: selectedGlyphRange) { _, usedRect, _, _, _ in
            let drawRect = NSRect(
                x: 0,
                y: usedRect.minY + origin.y,
                width: self.bounds.width,
                height: usedRect.height
            )
            self.editorTheme.currentLineBackground.setFill()
            drawRect.fill()
        }
    }

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

private struct JSONEditorTheme {
    let editorBackground: NSColor
    let foreground: NSColor
    let key: NSColor
    let string: NSColor
    let number: NSColor
    let keyword: NSColor
    let punctuation: NSColor
    let selectionBackground: NSColor
    let currentLineBackground: NSColor
    let lineNumberForeground: NSColor
    let rulerBackground: NSColor

    static let sublimeLike = JSONEditorTheme(
        editorBackground: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0),
        foreground: NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.95, alpha: 1.0),
        key: NSColor(calibratedRed: 0.98, green: 0.58, blue: 0.35, alpha: 1.0),
        string: NSColor(calibratedRed: 0.90, green: 0.80, blue: 0.47, alpha: 1.0),
        number: NSColor(calibratedRed: 0.69, green: 0.82, blue: 0.52, alpha: 1.0),
        keyword: NSColor(calibratedRed: 0.45, green: 0.77, blue: 0.98, alpha: 1.0),
        punctuation: NSColor(calibratedRed: 0.78, green: 0.81, blue: 0.87, alpha: 1.0),
        selectionBackground: NSColor(calibratedRed: 0.31, green: 0.36, blue: 0.49, alpha: 1.0),
        currentLineBackground: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.29, alpha: 0.9),
        lineNumberForeground: NSColor(calibratedRed: 0.53, green: 0.57, blue: 0.64, alpha: 1.0),
        rulerBackground: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)
    )
}

private enum JSONSyntaxHighlighter {
    private static let keyRegex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)")
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"")
    private static let numberRegex = try! NSRegularExpression(pattern: "\\b-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b")
    private static let keywordRegex = try! NSRegularExpression(pattern: "\\b(?:true|false|null)\\b")
    private static let punctuationRegex = try! NSRegularExpression(pattern: "[\\{\\}\\[\\]\\:\\,]")

    static func baseAttributes(for theme: JSONEditorTheme, font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.defaultTabInterval = font.pointSize * 2
        paragraphStyle.tabStops = []
        paragraphStyle.lineSpacing = 2

        return [
            .font: font,
            .foregroundColor: theme.foreground,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func highlight(textView: NSTextView, font: NSFont, theme: JSONEditorTheme) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length >= 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(for: theme, font: font), range: fullRange)

        apply(regex: stringRegex, color: theme.string, to: textStorage, in: fullRange)
        apply(regex: keyRegex, color: theme.key, to: textStorage, in: fullRange)
        apply(regex: numberRegex, color: theme.number, to: textStorage, in: fullRange)
        apply(regex: keywordRegex, color: theme.keyword, to: textStorage, in: fullRange)
        apply(regex: punctuationRegex, color: theme.punctuation, to: textStorage, in: fullRange)

        textStorage.endEditing()
    }

    private static func apply(regex: NSRegularExpression, color: NSColor, to textStorage: NSTextStorage, in range: NSRange) {
        let matches = regex.matches(in: textStorage.string, options: [], range: range)
        for match in matches where match.range.location != NSNotFound {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let theme: JSONEditorTheme

    init(textView: NSTextView, theme: JSONEditorTheme) {
        self.textView = textView
        self.theme = theme
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView else { return }
        guard let layoutManager = textView.layoutManager else { return }
        guard let textContainer = textView.textContainer else { return }

        theme.rulerBackground.setFill()
        bounds.fill()

        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let firstCharacter = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil).location
        var lineNumber = lineNumberForLocation(firstCharacter, in: textView.string as NSString)
        var glyphIndex = visibleGlyphRange.location

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: theme.lineNumberForeground
        ]

        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let charRange = (textView.string as NSString).lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)

            let y = lineRect.minY + relativePoint.y + 1
            let labelRect = NSRect(x: 0, y: y, width: ruleThickness - 8, height: 14)
            NSString(string: "\(lineNumber)").draw(in: labelRect, withAttributes: attrs)

            lineNumber += 1
            glyphIndex = NSMaxRange(glyphRange)
        }
    }

    private func lineNumberForLocation(_ location: Int, in text: NSString) -> Int {
        if location <= 0 { return 1 }
        let prefix = text.substring(to: min(location, text.length))
        return prefix.reduce(into: 1) { count, ch in
            if ch == "\n" { count += 1 }
        }
    }
}
