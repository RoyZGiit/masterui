import AppKit
import ApplicationServices

// MARK: - PermissionsManager

/// Manages checking and requesting macOS accessibility permissions.
class PermissionsManager {
    static let shared = PermissionsManager()

    /// Whether the system prompt has already been shown this launch.
    private var hasPromptedThisLaunch = false

    private init() {}

    /// Whether the app currently has accessibility permission.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Ensure accessibility permission is available, prompting only once per launch if needed.
    /// Call this lazily when an accessibility feature is first used—not on app startup.
    @discardableResult
    func ensureAccessibility() -> Bool {
        if hasAccessibilityPermission { return true }
        if !hasPromptedThisLaunch {
            hasPromptedThisLaunch = true
            promptForAccessibility()
        }
        return false
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
