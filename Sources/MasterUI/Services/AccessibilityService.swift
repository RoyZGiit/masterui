import ApplicationServices
import AppKit
import Foundation

// MARK: - AccessibilityService

/// Core service for interacting with other applications via the macOS Accessibility API.
class AccessibilityService {
    static let shared = AccessibilityService()

    private init() {}

    // MARK: - App Element

    /// Get the AXUIElement for a running application by its bundle ID.
    /// Lazily prompts for accessibility permission if not yet granted.
    func appElement(bundleID: String) -> AXUIElement? {
        guard PermissionsManager.shared.ensureAccessibility() else { return nil }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// Get all windows of an application.
    func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    /// Get the focused window of an application.
    func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        return appElement.elementAttribute(kAXFocusedWindowAttribute as String)
    }

    // MARK: - Element Reading

    /// Read the text value of an element.
    func readValue(_ element: AXUIElement) -> String? {
        return element.value
    }

    /// Read all text content from an element and its descendants.
    func readAllText(_ element: AXUIElement, maxDepth: Int = 10) -> String {
        var texts: [String] = []
        collectText(element, into: &texts, depth: 0, maxDepth: maxDepth)
        return texts.joined(separator: "\n")
    }

    private func collectText(_ element: AXUIElement, into texts: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        if let value = element.value, !value.isEmpty {
            texts.append(value)
        }

        for child in element.children() {
            collectText(child, into: &texts, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    // MARK: - Element Writing

    /// Set the text value of an element.
    @discardableResult
    func setValue(_ element: AXUIElement, text: String) -> Bool {
        return element.setValue(text)
    }

    /// Focus an element.
    @discardableResult
    func focus(_ element: AXUIElement) -> Bool {
        return element.setFocused(true)
    }

    // MARK: - Actions

    /// Perform an action on an element.
    @discardableResult
    func performAction(_ element: AXUIElement, action: String) -> Bool {
        return element.performAction(action)
    }

    // MARK: - App Activation

    /// Activate (bring to front) an app by its bundle ID.
    func activateApp(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return
        }
        app.activate(options: [.activateAllWindows])
    }

    /// Check if an app is running.
    func isAppRunning(bundleID: String) -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - Element at Position

    /// Get the AX element at a specific screen position.
    func elementAtPosition(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success else { return nil }
        return element
    }
}
