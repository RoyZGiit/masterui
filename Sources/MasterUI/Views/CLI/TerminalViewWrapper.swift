import SwiftUI
import SwiftTerm

// MARK: - TerminalViewCache

/// Caches terminal NSView instances so they survive SwiftUI view lifecycle.
/// Each CLI session gets a persistent terminal view that is reused when switching back.
class TerminalViewCache {
    static let shared = TerminalViewCache()

    private var views: [UUID: MasterUITerminalView] = [:]
    private var coordinators: [UUID: TerminalCoordinator] = [:]

    func getOrCreate(
        for session: CLISession,
        onStateChange: ((SessionState) -> Void)?
    ) -> (MasterUITerminalView, TerminalCoordinator) {
        if let view = views[session.id], let coordinator = coordinators[session.id] {
            // Update the state change callback (it may have changed)
            coordinator.onStateChange = onStateChange
            return (view, coordinator)
        }

        let coordinator = TerminalCoordinator(session: session, onStateChange: onStateChange)
        let view = MasterUITerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.processDelegate = coordinator
        view.idleCoordinator = coordinator

        // Appearance
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.optionAsMetaKey = true
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.9, alpha: 1.0)

        // Build environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let envStrings = env.map { "\($0.key)=\($0.value)" }

        // Start the process
        view.startProcess(
            executable: session.target.executablePath,
            args: session.target.arguments,
            environment: envStrings,
            currentDirectory: session.target.workingDirectory ?? NSHomeDirectory()
        )

        DispatchQueue.main.async {
            session.state = .running
        }

        views[session.id] = view
        coordinators[session.id] = coordinator

        return (view, coordinator)
    }

    func remove(sessionID: UUID) {
        if let view = views[sessionID] {
            view.terminate()
            view.removeFromSuperview()
        }
        views.removeValue(forKey: sessionID)
        coordinators.removeValue(forKey: sessionID)
    }

    func terminalView(for sessionID: UUID) -> MasterUITerminalView? {
        views[sessionID]
    }
}

// MARK: - TerminalCoordinator

/// Coordinator for terminal delegate callbacks and idle detection.
class TerminalCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    let session: CLISession
    var onStateChange: ((SessionState) -> Void)?
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 2.0

    init(session: CLISession, onStateChange: ((SessionState) -> Void)?) {
        self.session = session
        self.onStateChange = onStateChange
        super.init()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm handles PTY resize internally
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            self.session.title = title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Could update session working directory display in the future
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            self.session.state = .exited
            self.session.exitCode = exitCode
            self.onStateChange?(.exited)
        }
        idleTimer?.invalidate()
    }

    // MARK: - Idle Detection

    func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.session.state == .running {
                    self.session.state = .waitingForInput
                    self.session.lastActivityDate = Date()
                    self.onStateChange?(.waitingForInput)
                }
            }
        }

        // Mark as running when data is flowing
        DispatchQueue.main.async {
            if self.session.state != .running && self.session.state != .exited {
                self.session.state = .running
                self.onStateChange?(.running)
            }
            self.session.lastActivityDate = Date()
        }
    }
}

// MARK: - MasterUITerminalView

/// Custom subclass of LocalProcessTerminalView that hooks into data received
/// to support idle detection.
class MasterUITerminalView: LocalProcessTerminalView {
    weak var idleCoordinator: TerminalCoordinator?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        idleCoordinator?.resetIdleTimer()
    }
}

// MARK: - EnhancedTerminalViewWrapper

/// NSViewRepresentable that wraps a cached MasterUITerminalView.
/// Uses TerminalViewCache to persist terminal views across SwiftUI redraws.
///
/// IMPORTANT: Use `.id(session.id)` on this view to force recreation when the
/// focused session changes. This ensures `makeNSView` is called for each session.
struct EnhancedTerminalViewWrapper: NSViewRepresentable {
    let session: CLISession
    var onStateChange: ((SessionState) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let (termView, _) = TerminalViewCache.shared.getOrCreate(
            for: session,
            onStateChange: onStateChange
        )

        // Wrap in a container so SwiftUI doesn't fight with the terminal's layout
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true

        installTerminalView(termView, in: container)

        // Ensure keyboard focus after the view is added to the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            termView.window?.makeFirstResponder(termView)
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure the terminal view for the current session exists and is installed
        let (termView, _) = TerminalViewCache.shared.getOrCreate(
            for: session,
            onStateChange: onStateChange
        )

        // Check if the correct terminal view is already installed
        if termView.superview !== nsView {
            // Remove old subviews
            for subview in nsView.subviews {
                subview.removeFromSuperview()
            }
            installTerminalView(termView, in: nsView)
        }

        // Ensure keyboard focus
        DispatchQueue.main.async {
            if termView.window?.firstResponder !== termView {
                termView.window?.makeFirstResponder(termView)
            }
        }
    }

    /// Install a terminal view into a container with auto-layout constraints.
    private func installTerminalView(_ termView: MasterUITerminalView, in container: NSView) {
        termView.removeFromSuperview()
        termView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(termView)

        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: container.topAnchor),
            termView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            termView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
