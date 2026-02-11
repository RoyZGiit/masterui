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
        // Show dock icon (regular app)
        NSApp.setActivationPolicy(.regular)

        // Set up main menu (required for standard editing shortcuts in NSTextView)
        setupMainMenu()

        // Check accessibility permissions
        PermissionsManager.shared.checkAndRequestAccessibility()

        // Set up the floating panel
        panelController = FloatingPanelController()

        // Set up global hotkey
        hotkeyManager = HotkeyManager(panelController: panelController)
        hotkeyManager.register()

        // Set up menu bar status item
        setupStatusItem()

        // Show panel on launch
        panelController.showPanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.persistRuntimeState()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About MasterUI", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: "Hide MasterUI", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MasterUI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (enables standard text editing shortcuts)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        let findItem = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editMenu.addItem(findItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
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
