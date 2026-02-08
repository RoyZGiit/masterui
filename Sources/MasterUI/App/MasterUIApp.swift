import AppKit
import SwiftUI

// MARK: - App Entry Point

@main
struct MasterUIApp {
    static func main() {
        let args = CommandLine.arguments

        // Diagnostic mode: swift run MasterUI --diagnose <bundleID>
        if args.contains("--diagnose") {
            runDiagnostics(args: args)
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Run diagnostic commands and exit.
    static func runDiagnostics(args: [String]) {
        guard let idx = args.firstIndex(of: "--diagnose"),
              idx + 1 < args.count else {
            print("Usage: MasterUI --diagnose <bundleID>")
            print("       MasterUI --diagnose <bundleID> --inputs")
            print("       MasterUI --diagnose <bundleID> --tree")
            print("")
            print("Examples:")
            print("  MasterUI --diagnose com.todesktop.230313mzl4w4u92   # Cursor")
            print("  MasterUI --diagnose com.openai.chat                  # ChatGPT")
            print("  MasterUI --diagnose com.anthropic.claudefordesktop   # Claude")
            return
        }

        let bundleID = args[idx + 1]

        // Check accessibility
        if !AXIsProcessTrusted() {
            print("WARNING: Accessibility permission not granted!")
            print("Please go to System Settings > Privacy & Security > Accessibility")
            print("and add this application (or Terminal.app if running from terminal).\n")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        if args.contains("--inputs") {
            print(Diagnostics.findTextInputs(bundleID: bundleID))
        } else if args.contains("--tree") {
            print(Diagnostics.dumpFullTree(bundleID: bundleID, maxDepth: 6))
        } else {
            // Default: show both inputs and a shallow tree
            print(Diagnostics.findTextInputs(bundleID: bundleID))
            print("\n" + String(repeating: "=", count: 60) + "\n")
            print(Diagnostics.dumpFullTree(bundleID: bundleID, maxDepth: 4))
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: FloatingPanelController!
    private var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar only app)
        NSApp.setActivationPolicy(.accessory)

        // Check accessibility permissions
        PermissionsManager.shared.checkAndRequestAccessibility()

        // Set up the floating panel
        panelController = FloatingPanelController()

        // Set up global hotkey
        hotkeyManager = HotkeyManager(panelController: panelController)
        hotkeyManager.register()

        // Set up menu bar status item
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "MasterUI")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show MasterUI", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MasterUI", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func showPanel() {
        panelController.togglePanel()
    }

    @objc private func showSettings() {
        panelController.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
