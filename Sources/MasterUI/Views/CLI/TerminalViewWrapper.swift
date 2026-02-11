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
        
        // Enable clipboard integration
        view.allowMouseReporting = false // Disable mouse reporting so standard selection works better
        // view.enableOSC52 = true          // SwiftTerm 1.2.0 might not expose this property publicly yet

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

/// Coordinator for terminal delegate callbacks, idle detection, and history capture.
class TerminalCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    let session: CLISession
    var onStateChange: ((SessionState) -> Void)?
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 2.0

    // MARK: - History Capture State

    /// The user input pending to be paired with model output.
    var pendingInput: String?
    /// Accumulated raw output bytes since the last user input.
    private var outputBuffer = Data()

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
        DispatchQueue.main.async {
            self.session.currentDirectory = directory
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Flush any pending turn before marking as exited
        flushPendingTurn()

        DispatchQueue.main.async {
            self.session.state = .exited
            self.session.exitCode = exitCode
            self.onStateChange?(.exited)
        }
        idleTimer?.invalidate()
    }

    // MARK: - Output Accumulation

    /// Called from `MasterUITerminalView.dataReceived` to accumulate output bytes.
    func accumulateOutput(_ slice: ArraySlice<UInt8>) {
        outputBuffer.append(contentsOf: slice)
    }

    // MARK: - Turn Management

    /// When the user presses Enter, commit the previous turn (if any)
    /// and start a new one with the given input.
    func commitInputLine(_ input: String) {
        // Flush previous pending turn first
        flushPendingTurn()

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingInput = trimmed
        outputBuffer = Data()
    }

    /// Flush the pending turn into session history.
    /// Called when idle is detected or when a new input line arrives.
    func flushPendingTurn() {
        guard let input = pendingInput else { return }

        let rawOutput = String(data: outputBuffer, encoding: .utf8) ?? ""
        let cleaned = ANSICleaner.clean(rawOutput)

        if !cleaned.isEmpty {
            DispatchQueue.main.async {
                self.session.appendTurn(input: input, output: cleaned)
            }
        }

        pendingInput = nil
        outputBuffer = Data()
    }

    // MARK: - Idle Detection

    func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // When idle is detected, flush the pending turn
            self.flushPendingTurn()

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

// MARK: - ANSICleaner

/// Strips ANSI escape codes and cleans terminal output for history storage.
enum ANSICleaner {
    /// Clean raw terminal output: strip ANSI codes, handle carriage returns, normalize whitespace.
    static func clean(_ raw: String) -> String {
        // 1. Strip ANSI escape sequences (CSI, OSC, and simple escapes)
        var text = raw
        // CSI sequences: ESC [ ... final_byte
        text = text.replacingOccurrences(
            of: "\\x1B\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        // Also match \e as actual escape char
        text = text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        // OSC sequences: ESC ] ... BEL/ST
        text = text.replacingOccurrences(
            of: "\u{1B}\\].*?(\u{07}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
        // Simple escape sequences: ESC followed by single char
        text = text.replacingOccurrences(
            of: "\u{1B}[()][0-9A-Za-z]",
            with: "",
            options: .regularExpression
        )
        // Any remaining standalone ESC
        text = text.replacingOccurrences(of: "\u{1B}", with: "")

        // 2. Handle carriage returns: for each line, only keep content after last \r
        let lines = text.components(separatedBy: "\n").map { line -> String in
            if let lastCR = line.lastIndex(of: "\r") {
                return String(line[line.index(after: lastCR)...])
            }
            return line
        }

        // 3. Strip trailing whitespace per line and collapse multiple blank lines
        var result: [String] = []
        var lastWasBlank = false
        for line in lines {
            let trimmed = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if trimmed.isEmpty {
                if !lastWasBlank {
                    result.append("")
                }
                lastWasBlank = true
            } else {
                result.append(trimmed)
                lastWasBlank = false
            }
        }

        // 4. Trim leading/trailing blank lines
        while result.first?.isEmpty == true { result.removeFirst() }
        while result.last?.isEmpty == true { result.removeLast() }

        return result.joined(separator: "\n")
    }
}

// MARK: - MasterUITerminalView

/// Custom subclass of LocalProcessTerminalView that hooks into data received
/// to support idle detection and history capture.
class MasterUITerminalView: LocalProcessTerminalView {
    weak var idleCoordinator: TerminalCoordinator?

    /// Buffer for the current line being typed by the user.
    private var inputLineBuffer: String = ""

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        idleCoordinator?.resetIdleTimer()
        idleCoordinator?.accumulateOutput(slice)
    }

    /// Intercept all data sent from terminal to PTY to track user input.
    /// This is called for every keystroke and paste operation.
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        // Parse user-sent bytes to track input
        for byte in data {
            switch byte {
            case 0x0D: // CR (Enter)
                idleCoordinator?.commitInputLine(inputLineBuffer)
                inputLineBuffer = ""
            case 0x7F, 0x08: // DEL, BS (Backspace)
                if !inputLineBuffer.isEmpty {
                    inputLineBuffer.removeLast()
                }
            case 0x03: // ETX (Ctrl+C)
                inputLineBuffer = ""
            case 0x15: // NAK (Ctrl+U, clear line)
                inputLineBuffer = ""
            case 0x20...0x7E: // Printable ASCII
                inputLineBuffer.append(Character(UnicodeScalar(byte)))
            default:
                // Multi-byte UTF-8 or control chars — append printable UTF-8 later if needed
                break
            }
        }

        super.send(source: source, data: data)
    }

    // Enable standard copy command
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" {
                copy(self)
                return true
            } else if event.charactersIgnoringModifiers == "v" {
                paste(self)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // Ensure paste uses the correct pasteboard handling
    override func paste(_ sender: Any?) {
        if let string = NSPasteboard.general.string(forType: .string) {
            send(txt: string)
        }
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
