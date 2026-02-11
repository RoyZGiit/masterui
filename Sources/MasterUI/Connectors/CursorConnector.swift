import AppKit
import ApplicationServices
import Foundation

// MARK: - CursorConnector

/// Specialized connector for Cursor IDE.
///
/// Cursor is an Electron app whose chat input is a contenteditable div,
/// not exposed as a standard AXTextArea. So we use a keyboard-driven
/// approach: activate Cursor, focus the chat input via keyboard shortcut,
/// paste text from clipboard, and press Enter to send.
///
/// For reading responses, we traverse the AX tree looking for
/// `AXDOMIdentifier="bubble-*"` groups containing chat messages.
class CursorConnector: AppConnectorProtocol {
    let target: AITarget

    private let accessibilityService = AccessibilityService.shared
    private var responseTimer: Timer?
    private var lastBubbleCount: Int = 0
    private var lastResponseText: String = ""
    private var stableCount: Int = 0
    private var responseCallback: ((String, Bool) -> Void)?

    init(target: AITarget) {
        self.target = target
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) async -> Bool {
        guard isAppRunning else {
            print("[CursorConnector] Cursor is not running")
            return false
        }

        // Step 0: Check AX Health (Just for logging, don't stop)
        let isAXHealthy = checkAXHealth()
        if !isAXHealthy {
            print("[CursorConnector] WARNING: Cursor AX tree appears broken. Falling back to blind keyboard simulation.")
        }

        // Step 1: Activate Cursor and bring it to front
        print("[CursorConnector] Activating Cursor...")
        accessibilityService.activateApp(bundleID: target.bundleID)
        try? await Task.sleep(nanoseconds: 800_000_000) // Increased to 800ms to ensure focus

        // Step 2: Record current bubble count before sending (only if healthy)
        if isAXHealthy {
            lastBubbleCount = countBubbles()
            print("[CursorConnector] Pre-send bubble count: \(lastBubbleCount)")
        }

        // Step 3: Save clipboard, copy our text
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 4: Ensure Chat Panel is Open & Focused
        // Try Cmd+L (Cursor's shortcut to focus AI chat input)
        print("[CursorConnector] Sending Cmd+L (Focus Chat)...")
        simulateKeyPress(keyCode: 37, flags: .maskCommand) // 37 = 'L'
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms

        // Step 5: Select all existing text in the input (Cmd+A) and replace with paste
        // We do this blindly. If focus isn't in input, this might select other things, but it's the best bet.
        print("[CursorConnector] Sending Cmd+A...")
        simulateKeyPress(keyCode: 0, flags: .maskCommand) // 0 = 'A'
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Step 6: Paste our text
        print("[CursorConnector] Sending Cmd+V...")
        simulateKeyPress(keyCode: 9, flags: .maskCommand) // 9 = 'V'
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

        // Step 7: Send with Enter
        print("[CursorConnector] Sending Enter...")
        simulateKeyPress(keyCode: 36, flags: []) // 36 = Return
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        // Step 8: Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let previous = previousContent {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        
        print("[CursorConnector] Message sent sequence complete")
        return true
    }
    
    // Check if the AX tree is exposing meaningful data
    private func checkAXHealth() -> Bool {
        guard let appElement = accessibilityService.appElement(bundleID: target.bundleID) else { return false }
        guard let windows = appElement.elementAttribute(kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else { return false }
        
        // Check the first window for ANY meaningful content (DOM ID or Value)
        let window = windows[0]
        if hasMeaningfulContent(window, depth: 0, maxDepth: 5) {
            return true
        }
        
        return false
    }
    
    private func hasMeaningfulContent(_ element: AXUIElement, depth: Int, maxDepth: Int) -> Bool {
        if depth > maxDepth { return false }
        
        if let domId = element.stringAttribute("AXDOMIdentifier"), !domId.isEmpty { return true }
        if let value = element.value, !value.isEmpty { return true }
        if element.role == "AXWebArea" { return true }
        
        for child in element.children() {
            if hasMeaningfulContent(child, depth: depth + 1, maxDepth: maxDepth) {
                return true
            }
        }
        return false
    }

    // MARK: - Response Monitoring

    func startMonitoring(callback: @escaping (String, Bool) -> Void) {
        stopMonitoring()

        print("[CursorConnector] Starting monitoring...")
        
        responseCallback = callback
        lastResponseText = ""
        stableCount = 0

        // Initial health check
        if !checkAXHealth() {
             print("[CursorConnector] AX Tree broken. Entering recovery mode.")
             // Notify user once
             callback("✅ Message sent to Cursor.\n\n⚠️ MasterUI cannot read the response because Cursor's accessibility interface is not responding.\n\n👉 Please **RESTART CURSOR** to restore automatic reading.\n(MasterUI is watching and will auto-reconnect...)", true)
             
             // Start recovery poller (check every 2s)
             startRecoveryPolling()
             return
        }
        
        startNormalPolling()
    }
    
    private func startNormalPolling() {
        print("[CursorConnector] AX Health OK. Starting normal polling.")
        // Diagnostic: Dump UI tree to help debug structure issues
        Task {
            let debugInfo = Diagnostics.dumpFullTree(bundleID: target.bundleID, maxDepth: 8)
            print("[CursorConnector] UI Tree Dump:\n\(debugInfo)")
        }
        
        // Poll every 0.5 seconds for content
        responseTimer?.invalidate()
        responseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollResponse()
        }
    }
    
    private func startRecoveryPolling() {
        // Poll every 2 seconds to see if AX health is restored
        responseTimer?.invalidate()
        responseTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            print("[CursorConnector] Checking for AX recovery...")
            
            if self.checkAXHealth() {
                print("[CursorConnector] Cursor AX recovered! Switching to normal polling.")
                self.responseTimer?.invalidate()
                self.startNormalPolling()
                
                // Optionally notify user that we are back online?
                // For now, just let the next pollResponse update the UI with actual text.
            }
        }
    }

    func stopMonitoring() {
        responseTimer?.invalidate()
        responseTimer = nil
        responseCallback = nil
    }

    private func pollResponse() {
        guard let callback = responseCallback else { return }

        // Find the latest bubble's text content
        let latestText = readLatestBubbleText()

        if latestText != lastResponseText {
            lastResponseText = latestText
            stableCount = 0
            if !latestText.isEmpty {
                callback(latestText, false) // Still streaming
            }
        } else {
            stableCount += 1
            // After 2 seconds of stability (4 polls at 0.5s), consider complete
            if stableCount >= 4 && !lastResponseText.isEmpty {
                callback(lastResponseText, true) // Complete
                stopMonitoring()
            }
        }
    }

    // MARK: - Read Chat Bubbles

    /// Count the number of bubble groups in the chat panel.
    private func countBubbles() -> Int {
        guard let chatPanel = findChatPanel() else { return 0 }
        return findBubbles(in: chatPanel).count
    }

    /// Read the text content of the latest chat bubble.
    private func readLatestBubbleText() -> String {
        // Strategy 1: Try finding bubbles via IDs
        if let text = readLatestBubbleTextViaIDs(), !text.isEmpty {
            return text
        }
        
        // Strategy 2: Heuristic - Find focused input and look at siblings
        print("[CursorConnector] Strategy 1 failed. Trying Strategy 2 (Siblings of Input)...")
        if let text = readLatestBubbleTextViaInputSiblings(), !text.isEmpty {
            return text
        }
        
        return ""
    }
    
    private func readLatestBubbleTextViaIDs() -> String? {
        guard let chatPanel = findChatPanel() else { return nil }
        let bubbles = findBubbles(in: chatPanel)
        guard let lastBubble = bubbles.last else { 
            print("[CursorConnector] No bubbles found via ID")
            return nil 
        }

        let rawText = accessibilityService.readAllText(lastBubble, maxDepth: 10)
        let text = sanitizeResponseText(rawText)
        print("[CursorConnector] Read text from ID-based bubble (raw=\(rawText.count), clean=\(text.count))")
        return text.isEmpty ? nil : text
    }
    
    private func readLatestBubbleTextViaInputSiblings() -> String? {
        // We expect the input box to be focused or close to it
        guard let appElement = accessibilityService.appElement(bundleID: target.bundleID),
              let focused = accessibilityService.focusedWindow(of: appElement) else {
            return nil
        }
        
        // Find the input area (usually the focused element, or we search for it)
        // Since we just sent a message, the input box should be focused or we can find it by role
        
        // Let's look for a large group of text that IS NOT the input box
        // We'll traverse the window's children
        return findLastLargeTextGroup(in: focused)
    }
    
    private func findLastLargeTextGroup(in element: AXUIElement) -> String? {
        // Flatten the tree to a list of text blocks
        var textBlocks: [(AXUIElement, String)] = []
        collectTextBlocks(element, into: &textBlocks, depth: 0, maxDepth: 8)

        // Filter out short texts and likely input boxes (usually empty or "Type a message...")
        // We want the LAST significant text block

        for block in textBlocks.reversed() {
            let text = sanitizeResponseText(block.1)
            if !text.isEmpty {
                 print("[CursorConnector] Found candidate text block via heuristic: \(text.prefix(30))...")
                 return text
            }
        }

        return nil
    }
    
    private func collectTextBlocks(_ element: AXUIElement, into blocks: inout [(AXUIElement, String)], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        
        // If this element has text value, add it
        if let value = element.value, !value.isEmpty {
            blocks.append((element, value))
        }
        // Also check if it's a group that we can extract all text from
        else if element.role == "AXGroup" || element.role == "AXStaticText" {
             let allText = accessibilityService.readAllText(element, maxDepth: 2)
             if !allText.isEmpty {
                 blocks.append((element, allText))
             }
        }
        
        for child in element.children() {
            collectTextBlocks(child, into: &blocks, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    /// Find the chat panel root element (AXDOMIdentifier starts with "workbench.panel.aichat").
    private func findChatPanel() -> AXUIElement? {
        guard let appElement = accessibilityService.appElement(bundleID: target.bundleID) else {
            print("[CursorConnector] Failed to get app element for \(target.bundleID)")
            return nil
        }

        if let panel = findElementByDOMId(root: appElement, prefix: "workbench.panel.aichat", maxDepth: 15) {
            return panel
        }
        
        print("[CursorConnector] Chat panel not found via DOM ID, falling back to full app search")
        // Fallback: return the app element itself, so we search for bubbles everywhere
        return appElement
    }

    /// Find all bubble groups (AXDOMIdentifier starts with "bubble-").
    private func findBubbles(in element: AXUIElement) -> [AXUIElement] {
        var bubbles: [AXUIElement] = []
        collectBubbles(element, bubbles: &bubbles, depth: 0, maxDepth: 15)
        print("[CursorConnector] Found \(bubbles.count) bubbles")
        return bubbles
    }

    private func collectBubbles(_ element: AXUIElement, bubbles: inout [AXUIElement], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        if let domId = element.stringAttribute("AXDOMIdentifier"), domId.hasPrefix("bubble-") {
            bubbles.append(element)
            return // Don't search inside bubbles
        }

        for child in element.children() {
            collectBubbles(child, bubbles: &bubbles, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    /// Find an element whose AXDOMIdentifier starts with a given prefix.
    private func findElementByDOMId(root: AXUIElement, prefix: String, maxDepth: Int) -> AXUIElement? {
        return findElementByDOMIdRecursive(root, prefix: prefix, depth: 0, maxDepth: maxDepth)
    }

    private func findElementByDOMIdRecursive(_ element: AXUIElement, prefix: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        if let domId = element.stringAttribute("AXDOMIdentifier"), domId.hasPrefix(prefix) {
            return element
        }

        for child in element.children() {
            if let found = findElementByDOMIdRecursive(child, prefix: prefix, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }

        return nil
    }

    /// Keep AX text as-is (including multi-line content), only trim outer whitespace.
    private func sanitizeResponseText(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Activate App

    func activateApp() {
        accessibilityService.activateApp(bundleID: target.bundleID)
    }

    var isAppRunning: Bool {
        accessibilityService.isAppRunning(bundleID: target.bundleID)
    }

    // MARK: - Key Simulation

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
