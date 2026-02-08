import AppKit
import ApplicationServices

// MARK: - PermissionsManager

/// Manages checking and requesting macOS accessibility permissions.
class PermissionsManager {
    static let shared = PermissionsManager()

    private init() {}

    /// Whether the app currently has accessibility permission.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Check accessibility permission and prompt user to grant it if not available.
    func checkAndRequestAccessibility() {
        if !hasAccessibilityPermission {
            promptForAccessibility()
        }
    }

    /// Request accessibility permission with a system prompt.
    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
