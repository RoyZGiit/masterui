import ApplicationServices
import Foundation

// MARK: - AXUIElement Extensions

extension AXUIElement {

    // MARK: - Attribute Reading

    /// Get a string attribute value.
    func stringAttribute(_ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Get an integer attribute value.
    func intAttribute(_ attribute: String) -> Int? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Int
    }

    /// Get a boolean attribute value.
    func boolAttribute(_ attribute: String) -> Bool? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    /// Get an AXUIElement attribute value.
    func elementAttribute(_ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        // AXUIElement is a CFTypeRef, so we check if it's the right type
        let typeID = CFGetTypeID(value!)
        guard typeID == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Get the children of this element.
    func children() -> [AXUIElement] {
        var count: CFIndex = 0
        let countResult = AXUIElementGetAttributeValueCount(self, kAXChildrenAttribute as CFString, &count)
        guard countResult == .success, count > 0 else { return [] }

        var children: CFArray?
        let result = AXUIElementCopyAttributeValues(self, kAXChildrenAttribute as CFString, 0, count, &children)
        guard result == .success, let childrenArray = children else { return [] }

        return (0..<CFArrayGetCount(childrenArray)).compactMap { index in
            let ptr = CFArrayGetValueAtIndex(childrenArray, index)
            return unsafeBitCast(ptr, to: AXUIElement.self)
        }
    }

    // MARK: - Common Attributes

    /// The AX role of this element (e.g., "AXTextArea", "AXButton").
    var role: String? {
        stringAttribute(kAXRoleAttribute as String)
    }

    /// The AX role description.
    var roleDescription: String? {
        stringAttribute(kAXRoleDescriptionAttribute as String)
    }

    /// The title of this element.
    var title: String? {
        stringAttribute(kAXTitleAttribute as String)
    }

    /// The description of this element.
    var axDescription: String? {
        stringAttribute(kAXDescriptionAttribute as String)
    }

    /// The value of this element (text content for text fields).
    var value: String? {
        stringAttribute(kAXValueAttribute as String)
    }

    /// The accessibility identifier.
    var identifier: String? {
        stringAttribute(kAXIdentifierAttribute as String)
    }

    /// The subrole of this element.
    var subrole: String? {
        stringAttribute(kAXSubroleAttribute as String)
    }

    /// Whether this element is focused.
    var isFocused: Bool {
        boolAttribute(kAXFocusedAttribute as String) ?? false
    }

    // MARK: - Attribute Writing

    /// Set the value attribute (for text fields).
    @discardableResult
    func setValue(_ newValue: String) -> Bool {
        let result = AXUIElementSetAttributeValue(self, kAXValueAttribute as CFString, newValue as CFTypeRef)
        return result == .success
    }

    /// Set focus on this element.
    @discardableResult
    func setFocused(_ focused: Bool) -> Bool {
        let result = AXUIElementSetAttributeValue(self, kAXFocusedAttribute as CFString, focused as CFTypeRef)
        return result == .success
    }

    // MARK: - Actions

    /// Get the list of supported actions.
    var supportedActions: [String] {
        var actionsArray: CFArray?
        let result = AXUIElementCopyActionNames(self, &actionsArray)
        guard result == .success, let actions = actionsArray as? [String] else { return [] }
        return actions
    }

    /// Perform an action on this element.
    @discardableResult
    func performAction(_ action: String) -> Bool {
        let result = AXUIElementPerformAction(self, action as CFString)
        return result == .success
    }

    /// Press this element (convenience for AXPress action).
    @discardableResult
    func press() -> Bool {
        performAction(kAXPressAction as String)
    }

    /// Confirm on this element (convenience for AXConfirm action).
    @discardableResult
    func confirm() -> Bool {
        performAction(kAXConfirmAction as String)
    }

    // MARK: - Debug

    /// Print a human-readable description of this element.
    func debugDescription(depth: Int = 0) -> String {
        let indent = String(repeating: "  ", count: depth)
        var desc = "\(indent)[\(role ?? "?")] title=\"\(title ?? "")\" value=\"\(value?.prefix(50) ?? "")\" id=\"\(identifier ?? "")\"\n"

        if depth < 5 { // Limit depth to avoid infinite recursion
            for child in children() {
                desc += child.debugDescription(depth: depth + 1)
            }
        }

        return desc
    }
}
