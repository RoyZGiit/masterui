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
        coordinator.terminalView = view

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

    /// Latest user input. Used to filter possible terminal input echo.
    var pendingInput: String?
    /// Accumulated raw output bytes since the last user input (fallback).
    private var outputBuffer = Data()
    /// Reference to the terminal view for reading the buffer directly.
    weak var terminalView: MasterUITerminalView?
    /// The scroll-invariant row where the current turn's output starts.
    private var outputStartRow: Int = 0
    /// Current assistant block being updated while output streams in.
    private var activeAssistantBlockID: UUID?

    /// Move output start row to the line after current cursor so consumed text
    /// is not re-read and appended repeatedly on later idle flushes.
    private func advanceOutputStartRowPastCursor() {
        guard let view = terminalView else { return }
        let terminal = view.getTerminal()
        let topRow = terminal.getTopVisibleRow()
        let cursorY = terminal.getCursorLocation().y
        outputStartRow = max(0, topRow + cursorY + 1)
    }

    /// Finalize the current assistant block when terminal returns to prompt
    /// (i.e. it's waiting for next user input).
    private func markTurnBoundaryAtPrompt() {
        activeAssistantBlockID = nil
        pendingInput = nil
        outputBuffer = Data()
        advanceOutputStartRowPastCursor()
    }

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
        flushPendingTurn(force: true)

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
        // Capture any final assistant text before starting the next user block.
        flushPendingTurn(force: true)

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Start a new user block.
        if Thread.isMainThread {
            _ = session.appendBlock(role: .user, content: trimmed)
        } else {
            DispatchQueue.main.async {
                _ = self.session.appendBlock(role: .user, content: trimmed)
            }
        }

        pendingInput = trimmed
        outputBuffer = Data()
        activeAssistantBlockID = nil

        // Record where the output will start (the line after the current input line).
        if let view = terminalView {
            let terminal = view.getTerminal()
            let topRow = terminal.getTopVisibleRow()
            let cursorY = terminal.getCursorLocation().y
            outputStartRow = topRow + cursorY + 1
        }
    }

    /// Flush the pending turn into session history.
    /// Called when idle is detected or when a new input line arrives.
    ///
    /// - Parameter force: true when user switched tab or process is exiting.
    func flushPendingTurn(force: Bool = false) {
        // Ignore process startup noise before the first user input.
        if pendingInput == nil && activeAssistantBlockID == nil {
            if force {
                outputBuffer = Data()
                advanceOutputStartRowPastCursor()
            }
            return
        }

        let sanitized = currentSanitizedOutput()
        guard !sanitized.isEmpty else {
            if force {
                outputBuffer = Data()
                advanceOutputStartRowPastCursor()
            }
            return
        }

        upsertAssistantBlock(with: sanitized)
        outputBuffer = Data()

        if force {
            // On explicit flush, consume current region so next update only reads new rows.
            advanceOutputStartRowPastCursor()
        }
    }

    // MARK: - Idle Detection

    func resetIdleTimer() {
        // Timer setup must happen on main thread to ensure the run loop fires them.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.idleTimer?.invalidate()

            // Short idle (2s): update UI state and flush the pending turn.
            // This captures the AI output between two user inputs as soon as
            // the terminal goes idle (i.e. the AI is waiting for the next prompt).
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: self.idleThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.session.state == .running {
                    self.session.state = .waitingForInput
                    self.session.lastActivityDate = Date()
                    self.onStateChange?(.waitingForInput)
                    self.flushPendingTurn(force: true)
                    self.markTurnBoundaryAtPrompt()
                }
            }

            // Mark as running when data is flowing
            if self.session.state != .running && self.session.state != .exited {
                self.session.state = .running
                self.onStateChange?(.running)
            }
            self.session.lastActivityDate = Date()

            // Keep updating the same assistant block while output is streaming.
            self.flushPendingTurn()
        }
    }

    /// Build sanitized output snapshot for the current assistant block.
    private func currentSanitizedOutput() -> String {
        var cleaned = ""
        if let view = terminalView {
            cleaned = view.getBufferText(fromRow: outputStartRow)
        }
        if cleaned.isEmpty {
            let rawOutput = String(data: outputBuffer, encoding: .utf8) ?? ""
            cleaned = ANSICleaner.clean(rawOutput)
        }
        return HistoryOutputCleaner.cleanAssistantOutput(cleaned, pendingInput: pendingInput)
    }

    /// Create or update the active assistant block.
    private func upsertAssistantBlock(with content: String) {
        if let blockID = activeAssistantBlockID {
            if Thread.isMainThread {
                session.updateBlockContent(blockID: blockID, content: content)
            } else {
                DispatchQueue.main.async {
                    self.session.updateBlockContent(blockID: blockID, content: content)
                }
            }
            return
        }

        if Thread.isMainThread {
            activeAssistantBlockID = session.appendBlock(role: .assistant, content: content)
            pendingInput = nil
        } else {
            DispatchQueue.main.async {
                self.activeAssistantBlockID = self.session.appendBlock(role: .assistant, content: content)
                self.pendingInput = nil
            }
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

// MARK: - HistoryOutputCleaner

/// Cleans terminal output before persisting it as assistant history.
/// Removes lines that are likely user-input echo to prevent role confusion.
enum HistoryOutputCleaner {
    static func cleanAssistantOutput(_ text: String, pendingInput: String?) -> String {
        let input = pendingInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return "" }

        let lines = text.components(separatedBy: .newlines)
        var filtered: [String] = []
        filtered.reserveCapacity(lines.count)

        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if shouldDropAsInputEcho(line: line, pendingInput: input) {
                continue
            }
            filtered.append(line)
        }

        while filtered.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            filtered.removeFirst()
        }
        while filtered.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            filtered.removeLast()
        }

        return filtered.joined(separator: "\n")
    }

    private static func shouldDropAsInputEcho(line: String, pendingInput: String) -> Bool {
        guard !pendingInput.isEmpty else { return false }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Keep prompt-prefixed lines (e.g. "$ cmd") intact.
        // Only drop pure input echo lines equal to the user's input.
        return trimmed == pendingInput
    }
}

// MARK: - MasterUITerminalView

/// Custom subclass of LocalProcessTerminalView that hooks into data received
/// to support idle detection and history capture.
class MasterUITerminalView: LocalProcessTerminalView {
    weak var idleCoordinator: TerminalCoordinator?

    /// Buffer for the current line being typed by the user.
    private var inputLineBuffer: String = ""

    /// Read text content from the terminal buffer starting at the given scroll-invariant row
    /// up to the current cursor position. This reads the already-rendered text from SwiftTerm's
    /// buffer, bypassing the need to parse raw ANSI byte streams.
    func getBufferText(fromRow startRow: Int) -> String {
        let terminal = getTerminal()
        let topRow = terminal.getTopVisibleRow()
        let cursorY = terminal.getCursorLocation().y
        let currentRow = topRow + cursorY

        let start = max(0, startRow)
        guard start <= currentRow else { return "" }

        var lines: [String] = []
        for row in start...currentRow {
            if let bufLine = terminal.getScrollInvariantLine(row: row) {
                let text = bufLine.translateToString(trimRight: true)
                lines.append(text)
            }
        }

        // Trim trailing empty lines
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        idleCoordinator?.resetIdleTimer()
        idleCoordinator?.accumulateOutput(slice)
    }

    /// Intercept all data sent from terminal to PTY to track user input.
    /// This is called for every keystroke and paste operation.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)

        if bytes.count == 1 {
            // Single byte: handle control characters and printable ASCII
            let byte = bytes[0]
            switch byte {
            case 0x0D, 0x0A: // CR/LF (Enter)
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
                break // Other control characters
            }
        } else if bytes.first != 0x1B, let str = String(bytes: bytes, encoding: .utf8) {
            // Multi-byte UTF-8 text (Chinese, emoji, etc.) or pasted text.
            // Escape sequences (starting with 0x1B) are ignored for input tracking.
            for char in str {
                if char == "\r" || char == "\n" {
                    idleCoordinator?.commitInputLine(inputLineBuffer)
                    inputLineBuffer = ""
                } else if let ascii = char.asciiValue {
                    // ASCII: only append printable range
                    if ascii >= 0x20 && ascii < 0x7F {
                        inputLineBuffer.append(char)
                    }
                } else {
                    // Non-ASCII: Chinese, emoji, etc.
                    inputLineBuffer.append(char)
                }
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
