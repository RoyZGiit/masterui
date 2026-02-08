import ApplicationServices
import AppKit
import Foundation

// MARK: - TextInjector

/// Injects text into a target application's input field and triggers sending.
class TextInjector {
    static let shared = TextInjector()

    private let accessibilityService = AccessibilityService.shared
    private let elementFinder = ElementFinder.shared

    private init() {}

    // MARK: - Inject and Send

    /// Inject text into the target app's input field and trigger send.
    /// Returns true if the injection was successful.
    @discardableResult
    func injectAndSend(target: AITarget, text: String) async -> Bool {
        guard let inputElement = elementFinder.findElement(bundleID: target.bundleID, locator: target.inputLocator) else {
            print("[TextInjector] Could not find input element for \(target.name)")
            return false
        }

        // Step 1: Focus the input element
        accessibilityService.focus(inputElement)

        // Brief pause for focus to take effect
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Step 2: Inject text
        let injected = injectText(into: inputElement, text: text, bundleID: target.bundleID)
        guard injected else {
            print("[TextInjector] Failed to inject text into \(target.name)")
            return false
        }

        // Brief pause for text to be processed
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Step 3: Trigger send
        triggerSend(target: target, inputElement: inputElement)

        return true
    }

    // MARK: - Text Injection

    /// Try to inject text into an element, with fallback strategies.
    private func injectText(into element: AXUIElement, text: String, bundleID: String) -> Bool {
        // Strategy 1: Direct AXValue set
        if accessibilityService.setValue(element, text: text) {
            print("[TextInjector] Text injected via AXValue")
            return true
        }

        // Strategy 2: Clipboard paste fallback
        print("[TextInjector] AXValue failed, trying clipboard paste...")
        return clipboardPaste(text: text, into: element, bundleID: bundleID)
    }

    /// Fallback: Copy text to clipboard and simulate Cmd+V paste.
    private func clipboardPaste(text: String, into element: AXUIElement, bundleID: String) -> Bool {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Focus the element and the app
        accessibilityService.focus(element)
        accessibilityService.activateApp(bundleID: bundleID)

        // Simulate Cmd+V
        simulateKeyPress(keyCode: 9, flags: .maskCommand) // 9 = 'V' key

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return true
    }

    // MARK: - Trigger Send

    /// Trigger the send action based on the target's configuration.
    private func triggerSend(target: AITarget, inputElement: AXUIElement) {
        switch target.sendMethod {
        case .enterKey:
            simulateKeyPress(keyCode: 36, flags: []) // 36 = Return key

        case .cmdEnterKey:
            simulateKeyPress(keyCode: 36, flags: .maskCommand)

        case .clickSend:
            // Try to find and click a send button near the input
            // Look for a button as a sibling or nearby element
            if let sendButton = findSendButton(near: inputElement, bundleID: target.bundleID) {
                sendButton.press()
            } else {
                // Fallback to Enter key
                simulateKeyPress(keyCode: 36, flags: [])
            }
        }
    }

    /// Try to find a send button near the input element.
    private func findSendButton(near inputElement: AXUIElement, bundleID: String) -> AXUIElement? {
        // Simple heuristic: look for a button with common send-related titles
        let sendLocator = ElementLocator(
            role: "AXButton",
            titlePattern: "(?i)(send|submit|发送|提交)",
            deepSearch: true
        )

        return elementFinder.findElement(bundleID: bundleID, locator: sendLocator)
    }

    // MARK: - Key Simulation

    /// Simulate a key press using CGEvent.
    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
