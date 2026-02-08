import AppKit
import SwiftUI
import Combine

// MARK: - PanelLayout

enum PanelLayout {
    case chat
    case terminal

    var defaultSize: NSSize {
        switch self {
        case .chat: return NSSize(width: 520, height: 600)
        case .terminal: return NSSize(width: 1000, height: 700)
        }
    }

    var minSize: NSSize {
        switch self {
        case .chat: return NSSize(width: 480, height: 400)
        case .terminal: return NSSize(width: 700, height: 500)
        }
    }
}

// MARK: - Custom NSPanel

/// A floating panel window that stays on top of all windows,
/// styled with vibrancy and rounded corners (Spotlight-like).
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating behavior
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false

        // Appearance
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false

        // Show on all spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Animation
        animationBehavior = .utilityWindow

        // Default min size
        minSize = PanelLayout.chat.minSize
    }

    /// Intercept key equivalents for terminal shortcuts (Cmd+T, Cmd+W, Cmd+1-9)
    /// before they reach the terminal view.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              AppState.shared.viewMode == .cliSessions else {
            return super.performKeyEquivalent(with: event)
        }

        let sessionManager = AppState.shared.cliSessionManager

        switch event.charactersIgnoringModifiers {
        case "t":
            // Cmd+T: New session (handled by posting notification)
            NotificationCenter.default.post(name: .newCLISession, object: nil)
            return true
        case "w":
            // Cmd+W: Close focused session
            if let focusedID = sessionManager.focusedSessionID {
                sessionManager.closeSession(focusedID)
                return true
            }
        default:
            // Cmd+1 through Cmd+9: Switch sessions
            if let chars = event.charactersIgnoringModifiers,
               let digit = chars.first?.wholeNumberValue,
               digit >= 1 && digit <= 9 {
                let index = digit - 1
                if index < sessionManager.sessions.count {
                    sessionManager.focusSession(sessionManager.sessions[index].id)
                    return true
                }
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newCLISession = Notification.Name("MasterUI.newCLISession")
}

// MARK: - FloatingPanelController

class FloatingPanelController: ObservableObject {
    private var panel: FloatingPanel?
    private let appState = AppState.shared
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    func togglePanel() {
        if let panel = panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        if panel == nil {
            createPanel()
            observeViewMode()
        }

        guard let panel = panel else { return }

        // Size based on current mode
        let layout: PanelLayout = appState.viewMode == .cliSessions ? .terminal : .chat
        panel.minSize = layout.minSize

        // Fill the screen (visible area)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrame(screenFrame, display: true)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func resizePanel(to layout: PanelLayout) {
        guard let panel = panel else { return }

        let newSize = layout.defaultSize
        panel.minSize = layout.minSize

        // Keep center position during resize
        let currentFrame = panel.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - newSize.width / 2,
            y: currentFrame.midY - newSize.height / 2
        )

        // Clamp to screen bounds
        var newFrame = NSRect(origin: newOrigin, size: newSize)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            newFrame.origin.x = max(screenFrame.minX, min(newFrame.origin.x, screenFrame.maxX - newFrame.width))
            newFrame.origin.y = max(screenFrame.minY, min(newFrame.origin.y, screenFrame.maxY - newFrame.height))
        }

        panel.animator().setFrame(newFrame, display: true)
    }

    func showSettings() {
        if let settingsWindow = settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MasterUI Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    private func createPanel() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600))

        let contentView = PanelContentView()
            .environmentObject(appState)

        // Wrap in visual effect view for vibrancy
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect

        self.panel = panel
    }

    /// Observe view mode changes to resize the panel accordingly.
    private func observeViewMode() {
        appState.$viewMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                let layout: PanelLayout = mode == .cliSessions ? .terminal : .chat
                self?.resizePanel(to: layout)
            }
            .store(in: &cancellables)
    }
}
