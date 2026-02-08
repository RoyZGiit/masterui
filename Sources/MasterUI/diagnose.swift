// Diagnostic utility - can be called from the app for debugging.
// This file adds a command-line diagnostic mode to MasterUI.

import ApplicationServices
import AppKit
import Foundation

/// Run diagnostics on a target app's accessibility tree.
enum Diagnostics {

    /// Dump the full AX tree of an app, with more detail than the default debug dump.
    static func dumpFullTree(bundleID: String, maxDepth: Int = 12) -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return "ERROR: App with bundleID '\(bundleID)' is not running."
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var output = "=== AX Diagnostics for \(bundleID) (pid: \(app.processIdentifier)) ===\n"
        output += "App name: \(app.localizedName ?? "unknown")\n"
        output += "Is active: \(app.isActive)\n\n"

        // Check if we can access the app at all
        var value: AnyObject?
        let testResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        if testResult == .apiDisabled {
            output += "ERROR: Accessibility API is DISABLED. Please grant permission in System Settings > Privacy & Security > Accessibility.\n"
            return output
        }
        if testResult == .notImplemented {
            output += "ERROR: App does not implement Accessibility.\n"
            return output
        }
        if testResult != .success {
            output += "ERROR: Cannot access app's windows. AXError: \(testResult.rawValue)\n"
            return output
        }

        guard let windows = value as? [AXUIElement] else {
            output += "ERROR: No windows found.\n"
            return output
        }

        output += "Found \(windows.count) window(s)\n\n"

        for (i, window) in windows.enumerated() {
            output += "--- Window \(i) ---\n"
            output += dumpElement(window, depth: 0, maxDepth: maxDepth)
            output += "\n"
        }

        return output
    }

    /// Dump a single element and its children recursively.
    static func dumpElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> String {
        guard depth < maxDepth else {
            return String(repeating: "  ", count: depth) + "... (max depth reached)\n"
        }

        let indent = String(repeating: "  ", count: depth)
        let role = element.role ?? "?"
        let title = element.title ?? ""
        let identifier = element.identifier ?? ""
        let desc = element.axDescription ?? ""
        let val = element.value ?? ""
        let subrole = element.subrole ?? ""
        let focused = element.isFocused

        var line = "\(indent)[\(role)]"
        if !subrole.isEmpty { line += " subrole=\"\(subrole)\"" }
        if !title.isEmpty { line += " title=\"\(title.prefix(80))\"" }
        if !identifier.isEmpty { line += " id=\"\(identifier)\"" }
        if !desc.isEmpty { line += " desc=\"\(desc.prefix(80))\"" }
        if !val.isEmpty { line += " value=\"\(val.prefix(60))\"" }
        if focused { line += " [FOCUSED]" }

        let actions = element.supportedActions
        if !actions.isEmpty {
            line += " actions=[\(actions.joined(separator: ","))]"
        }

        line += "\n"

        var output = line

        for child in element.children() {
            output += dumpElement(child, depth: depth + 1, maxDepth: maxDepth)
        }

        return output
    }

    /// Find all text input elements in an app (AXTextArea, AXTextField, AXTextInput, etc.)
    static func findTextInputs(bundleID: String) -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return "ERROR: App not running."
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var inputs: [(depth: Int, role: String, identifier: String, title: String, value: String, desc: String)] = []

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            return "ERROR: Cannot access windows."
        }

        for window in windows {
            findTextInputsRecursive(window, depth: 0, maxDepth: 15, inputs: &inputs)
        }

        if inputs.isEmpty {
            return "No text input elements found in \(bundleID)."
        }

        var output = "Found \(inputs.count) text input element(s) in \(bundleID):\n\n"
        for (i, input) in inputs.enumerated() {
            output += "  [\(i)] role=\(input.role)"
            if !input.identifier.isEmpty { output += " id=\"\(input.identifier)\"" }
            if !input.title.isEmpty { output += " title=\"\(input.title.prefix(50))\"" }
            if !input.value.isEmpty { output += " value=\"\(input.value.prefix(50))\"" }
            if !input.desc.isEmpty { output += " desc=\"\(input.desc.prefix(50))\"" }
            output += " (depth=\(input.depth))\n"
        }

        return output
    }

    private static func findTextInputsRecursive(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        inputs: inout [(depth: Int, role: String, identifier: String, title: String, value: String, desc: String)]
    ) {
        guard depth < maxDepth else { return }

        let role = element.role ?? ""
        let textRoles = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]

        if textRoles.contains(role) {
            inputs.append((
                depth: depth,
                role: role,
                identifier: element.identifier ?? "",
                title: element.title ?? "",
                value: element.value ?? "",
                desc: element.axDescription ?? ""
            ))
        }

        for child in element.children() {
            findTextInputsRecursive(child, depth: depth + 1, maxDepth: maxDepth, inputs: &inputs)
        }
    }
}
