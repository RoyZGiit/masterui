import ApplicationServices
import Foundation

// MARK: - ElementFinder

/// Traverses the AX tree of another app to find specific UI elements
/// based on an ElementLocator configuration.
class ElementFinder {
    static let shared = ElementFinder()

    private let accessibilityService = AccessibilityService.shared

    private init() {}

    // MARK: - Find Element

    /// Find a UI element in the target app matching the given locator.
    func findElement(bundleID: String, locator: ElementLocator) -> AXUIElement? {
        guard locator.isConfigured else { return nil }

        guard let appElement = accessibilityService.appElement(bundleID: bundleID) else {
            print("[ElementFinder] App not found: \(bundleID)")
            return nil
        }

        // Try focused window first, then all windows
        if let focusedWindow = accessibilityService.focusedWindow(of: appElement) {
            if let found = searchElement(in: focusedWindow, locator: locator) {
                return found
            }
        }

        // Search all windows
        for window in accessibilityService.windows(of: appElement) {
            if let found = searchElement(in: window, locator: locator) {
                return found
            }
        }

        return nil
    }

    // MARK: - Search Strategies

    private func searchElement(in root: AXUIElement, locator: ElementLocator) -> AXUIElement? {
        if locator.deepSearch {
            return deepSearch(root: root, locator: locator)
        } else if let pathHint = locator.pathHint, !pathHint.isEmpty {
            return pathGuidedSearch(root: root, pathHint: pathHint, locator: locator)
        } else {
            return deepSearch(root: root, locator: locator)
        }
    }

    /// Deep (recursive) search of the AX tree for a matching element.
    private func deepSearch(root: AXUIElement, locator: ElementLocator, depth: Int = 0, maxDepth: Int = 15) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        var matches: [AXUIElement] = []
        deepSearchCollect(root: root, locator: locator, depth: depth, maxDepth: maxDepth, matches: &matches)

        if let index = locator.matchIndex {
            return index < matches.count ? matches[index] : nil
        }

        return matches.first
    }

    private func deepSearchCollect(root: AXUIElement, locator: ElementLocator, depth: Int, maxDepth: Int, matches: inout [AXUIElement]) {
        guard depth < maxDepth else { return }

        if matchesLocator(root, locator: locator) {
            matches.append(root)
        }

        for child in root.children() {
            deepSearchCollect(root: child, locator: locator, depth: depth + 1, maxDepth: maxDepth, matches: &matches)
        }
    }

    /// Path-guided search following role hints in order.
    private func pathGuidedSearch(root: AXUIElement, pathHint: [String], locator: ElementLocator) -> AXUIElement? {
        guard !pathHint.isEmpty else { return nil }

        var currentElements: [AXUIElement] = [root]

        for roleHint in pathHint {
            var nextElements: [AXUIElement] = []
            for element in currentElements {
                for child in element.children() {
                    if child.role == roleHint {
                        nextElements.append(child)
                    }
                }
            }
            currentElements = nextElements

            if currentElements.isEmpty {
                // Fallback: try deep search from current position
                break
            }
        }

        // Filter by additional locator criteria
        let filtered = currentElements.filter { matchesLocator($0, locator: locator, skipRole: true) }

        if let index = locator.matchIndex {
            return index < filtered.count ? filtered[index] : nil
        }
        return filtered.first ?? currentElements.first
    }

    // MARK: - Matching

    /// Check if an element matches the given locator criteria.
    func matchesLocator(_ element: AXUIElement, locator: ElementLocator, skipRole: Bool = false) -> Bool {
        // Check role
        if !skipRole, let expectedRole = locator.role {
            guard element.role == expectedRole else { return false }
        }

        // Check identifier
        if let expectedID = locator.identifier {
            guard element.identifier == expectedID else { return false }
        }

        // Check title pattern
        if let pattern = locator.titlePattern {
            guard let title = element.title,
                  title.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }

        // Check description pattern
        if let pattern = locator.descriptionPattern {
            guard let desc = element.axDescription,
                  desc.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }

        // Check value pattern
        if let pattern = locator.valuePattern {
            guard let val = element.value,
                  val.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }

        return true
    }

    // MARK: - Debug: Dump AX Tree

    /// Dump the entire AX tree of an app for debugging purposes.
    func dumpTree(bundleID: String, maxDepth: Int = 8) -> String {
        guard let appElement = accessibilityService.appElement(bundleID: bundleID) else {
            return "App not found: \(bundleID)"
        }

        var output = "=== AX Tree for \(bundleID) ===\n"
        for window in accessibilityService.windows(of: appElement) {
            output += window.debugDescription(depth: 0)
        }
        return output
    }
}
