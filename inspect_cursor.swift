
import ApplicationServices
import AppKit
import Foundation

// Helper to get AXUIElement children
func getChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if result == .success, let children = value as? [AXUIElement] {
        return children
    }
    return []
}

// Helper to get attribute string
func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if result == .success, let str = value as? String {
        return str
    }
    return nil
}

func dumpElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    if depth > maxDepth { return }
    
    let indent = String(repeating: "  ", count: depth)
    let role = getStringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
    let subrole = getStringAttribute(element, kAXSubroleAttribute as String) ?? ""
    let title = getStringAttribute(element, kAXTitleAttribute as String) ?? ""
    let domId = getStringAttribute(element, "AXDOMIdentifier") ?? ""
    let valueStr = getStringAttribute(element, kAXValueAttribute as String) ?? ""
    let desc = getStringAttribute(element, kAXDescriptionAttribute as String) ?? ""
    
    var info = "\(indent)[\(role)]"
    if !subrole.isEmpty { info += " subrole=\(subrole)" }
    if !title.isEmpty { info += " title='\(title)'" }
    if !domId.isEmpty { info += " domId='\(domId)'" }
    if !valueStr.isEmpty { info += " value='\(valueStr.prefix(30))...'" }
    if !desc.isEmpty { info += " desc='\(desc)'" }
    
    // Check for special roles that might contain content
    if role == "AXWebArea" {
        info += " <--- WEB AREA FOUND"
    }
    
    print(info)
    
    // Always dig into Groups and WebAreas
    let children = getChildren(element)
    if !children.isEmpty {
        for child in children {
            dumpElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

// Main
let bundleID = "com.todesktop.230313mzl4w4u92"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("Cursor is not running")
    exit(1)
}

print("Found Cursor (pid: \(app.processIdentifier))")
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// Check if we can access windows
var value: AnyObject?
let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
if result != .success {
    print("Cannot access windows. Error: \(result.rawValue)")
    print("Please ensure Terminal has Accessibility permissions.")
    exit(1)
}

guard let windows = value as? [AXUIElement] else {
    print("No windows found")
    exit(1)
}

print("Found \(windows.count) windows")
for (i, window) in windows.enumerated() {
    print("--- Window \(i) ---")
    // Increase max depth to find nested content
    dumpElement(window, depth: 0, maxDepth: 20)
}
