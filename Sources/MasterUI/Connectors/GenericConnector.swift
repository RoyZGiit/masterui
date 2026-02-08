import AppKit
import ApplicationServices
import Foundation

// MARK: - GenericConnector

/// A generic connector that uses Accessibility API to interact with any target app.
/// Works with any app that has accessible text input/output elements.
///
/// Injection strategy:
/// 1. Try to find an AXTextArea via element locator and set AXValue directly
/// 2. If that fails, fall back to: activate app -> focus -> clipboard paste
class GenericConnector: AppConnectorProtocol {
    let target: AITarget

    private let textInjector = TextInjector.shared
    private let responseMonitor = ResponseMonitor.shared
    private let accessibilityService = AccessibilityService.shared

    init(target: AITarget) {
        self.target = target
    }

    func sendMessage(_ text: String) async -> Bool {
        guard isAppRunning else {
            print("[GenericConnector] \(target.name) is not running")
            return false
        }

        // Strategy 1: Try the standard AX-based injection
        let axSuccess = await textInjector.injectAndSend(target: target, text: text)
        if axSuccess {
            return true
        }

        // Strategy 2: Keyboard-driven fallback (activate app, paste, enter)
        print("[GenericConnector] AX injection failed, trying keyboard fallback for \(target.name)")
        return await keyboardFallback(text: text)
    }

    /// Fallback: activate the app, paste text, and press enter.
    private func keyboardFallback(text: String) async -> Bool {
        // Activate the app
        print("[GenericConnector] Activating \(target.name)...")
        accessibilityService.activateApp(bundleID: target.bundleID)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s wait

        // Save and set clipboard
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Paste with Cmd+V
        print("[GenericConnector] Sending Cmd+V...")
        simulateKeyPress(keyCode: 9, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Send with Enter or Cmd+Enter depending on config
        print("[GenericConnector] Sending Enter (method: \(target.sendMethod))...")
        switch target.sendMethod {
        case .enterKey:
            simulateKeyPress(keyCode: 36, flags: [])
        case .cmdEnterKey:
            simulateKeyPress(keyCode: 36, flags: .maskCommand)
        case .clickSend:
            simulateKeyPress(keyCode: 36, flags: []) // fallback to Enter
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let previous = previousContent {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return true
    }

    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func startMonitoring(callback: @escaping (String, Bool) -> Void) {
        responseMonitor.startMonitoring(target: target, callback: callback)
    }

    func stopMonitoring() {
        responseMonitor.stopMonitoring(targetID: target.id)
    }

    func activateApp() {
        accessibilityService.activateApp(bundleID: target.bundleID)
    }

    var isAppRunning: Bool {
        accessibilityService.isAppRunning(bundleID: target.bundleID)
    }
}
