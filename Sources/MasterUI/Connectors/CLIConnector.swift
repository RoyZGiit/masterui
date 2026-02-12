
import Foundation

// MARK: - CLIConnector

/// Connector for interacting with Command Line Interface (CLI) tools.
/// Uses a Pseudo-Terminal (PTY) to support interactive tools like `claude` or `python`.
class CLIConnector: AppConnectorProtocol {
    let target: AITarget
    
    private let ptyManager = PTYManager.shared
    private var ptyProcess: PTYManager.PTYProcess?
    private var monitoringTask: Task<Void, Never>?
    private var isRunningInternal: Bool = false
    
    // Callback for streaming output
    private var responseCallback: ((String, Bool) -> Void)?
    
    // Buffer for accumulating output (to handle ANSI codes or partial reads)
    private var outputBuffer: String = ""
    
    init(target: AITarget) {
        self.target = target
    }
    
    // MARK: - AppConnectorProtocol
    
    var isAppRunning: Bool {
        return isRunningInternal && ptyProcess != nil
    }
    
    func activateApp() {
        // For CLI, "activating" might mean ensuring the process is running
        // or just logging. We can't really "bring to front" a background PTY process
        // unless we wrap it in a Terminal window, but here we run it headless.
        print("[CLIConnector] Activate called for \(target.name) (noop)")
    }
    
    func sendMessage(_ text: String) async -> Bool {
        guard let masterHandle = ptyProcess?.masterFileHandle else {
            // If process not running, try to start it
            if startProcess() {
                // Wait a bit for startup
                try? await Task.sleep(nanoseconds: 500_000_000)
            } else {
                return false
            }
            return await sendMessage(text)
        }
        
        // Append newline if not present, as CLI usually expects Enter
        let textToSend = text.hasSuffix("\n") ? text : text + "\n"
        
        guard let data = textToSend.data(using: .utf8) else { return false }
        
        do {
            try masterHandle.write(contentsOf: data)
            print("[CLIConnector] Sent \(data.count) bytes to PTY")
            return true
        } catch {
            print("[CLIConnector] Failed to write to PTY: \(error)")
            return false
        }
    }
    
    func startMonitoring(callback: @escaping (String, Bool) -> Void) {
        self.responseCallback = callback
        
        // If not already running, start the process
        if ptyProcess == nil {
            _ = startProcess()
        }
        
        // The actual reading loop happens in `startReadingLoop` which is triggered by startProcess
        // Here we just ensure the callback is updated
    }
    
    func stopMonitoring() {
        responseCallback = nil
        // We generally don't kill the process just because we stopped monitoring
        // unless we want to save resources. For interactive sessions, we keep it alive.
    }
    
    // MARK: - Process Management
    
    private func startProcess() -> Bool {
        guard !target.executablePath.isEmpty else {
            print("[CLIConnector] Error: No executable path provided")
            return false
        }
        
        do {
            print("[CLIConnector] Starting PTY process: \(target.executablePath) \(target.arguments)")
            let process = try ptyManager.startProcess(
                executable: target.executablePath,
                arguments: target.arguments,
                environment: ShellEnvironment.resolved,
                workingDirectory: target.workingDirectory
            )
            
            self.ptyProcess = process
            self.isRunningInternal = true
            
            // Start reading loop
            startReadingLoop(fileHandle: process.masterFileHandle)
            
            return true
        } catch {
            print("[CLIConnector] Failed to start PTY process: \(error)")
            return false
        }
    }
    
    private func terminateProcess() {
        if let pid = ptyProcess?.processID {
            kill(pid, SIGTERM)
        }
        ptyProcess = nil
        isRunningInternal = false
        monitoringTask?.cancel()
    }
    
    // MARK: - Reading Loop
    
    private func startReadingLoop(fileHandle: FileHandle) {
        monitoringTask = Task {
            // We use a dedicated thread/task for blocking read
            // FileHandle.availableData is blocking if we don't handle it carefully
            
            // Note: In Swift concurrency, doing blocking IO on FileHandle can be tricky.
            // We'll use the readabilityHandler for a cleaner async approach if possible,
            // or a loop with availableData.
            
            fileHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF reached
                    print("[CLIConnector] PTY EOF reached")
                    handle.readabilityHandler = nil
                    self?.handleProcessExit()
                    return
                }
                
                self?.handleOutputData(data)
            }
        }
    }
    
    private func handleProcessExit() {
        DispatchQueue.main.async {
            self.isRunningInternal = false
            self.ptyProcess = nil
            // Notify callback about exit?
            self.responseCallback?("[Process exited]", true)
        }
    }
    
    private func handleOutputData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        DispatchQueue.main.async {
            // Simple accumulation for now.
            // In a real terminal app, we would parse ANSI codes here.
            // For now, we append raw text.
            
            // We strip some common ANSI codes for better readability in plain text view
            let cleanText = self.stripANSI(from: string)
            
            // NOTE: MasterUI's chat interface expects the "full" response each time currently,
            // or at least that's how Connector worked (streaming updates).
            // We append to our buffer.
            self.outputBuffer += cleanText
            
            // Send update
            // We mark isComplete as false always for CLI, because it's an endless stream
            self.responseCallback?(self.outputBuffer, false)
        }
    }
    
    private func stripANSI(from text: String) -> String {
        var result = text
        
        // 1. Strip OSC codes (Operating System Command) e.g., hyperlinks ]8;;...
        // Pattern: \x1B] ... \x07
        let oscPattern = "\\u001B\\][^\\u0007]*\\u0007"
        result = result.replacingOccurrences(of: oscPattern, with: "", options: .regularExpression)
        
        // 2. Strip CSI codes (Control Sequence Introducer) e.g., colors, cursor movements
        // Pattern matches: ESC [ (optional params) (optional intermediates) (final byte)
        // Includes support for private modes (like ?25l)
        let csiPattern = "\\u001B\\[[0-9;?]*[ -/]*[@-~]"
        result = result.replacingOccurrences(of: csiPattern, with: "", options: .regularExpression)
        
        return result
    }
}
