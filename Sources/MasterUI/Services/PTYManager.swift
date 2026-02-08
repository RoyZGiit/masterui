
import Foundation

// MARK: - PTYManager

/// Manages Pseudo-Terminal (PTY) interactions for running CLI tools interactively.
class PTYManager {
    static let shared = PTYManager()
    
    private init() {}
    
    /// Result of starting a process in a PTY.
    struct PTYProcess {
        let processID: pid_t
        let masterFileHandle: FileHandle
    }
    
    /// Start a CLI command in a pseudo-terminal.
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/bin/bash", "/usr/local/bin/claude")
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - workingDirectory: Optional working directory
    /// - Returns: A PTYProcess object containing the PID and the master file handle for I/O.
    func startProcess(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) throws -> PTYProcess {
        
        // 1. Open PTY master/slave pair
        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        
        if openpty(&masterFD, &slaveFD, nil, nil, nil) == -1 {
            throw PTYError.openPTYFailed
        }
        
        // 2. Use posix_spawn instead of fork
        // Set up file actions to map the slave PTY to stdin/out/err
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        
        // dup2 slaveFD to 0, 1, 2
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        
        // Close original fds in child
        posix_spawn_file_actions_addclose(&fileActions, masterFD)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)
        
        // Prepare args
        let argv = [executable] + arguments
        let cArgs = argv.map { $0.withCString { strdup($0) } } + [nil]
        defer { cArgs.forEach { free($0) } }
        
        // Prepare env
        var env = environment ?? ProcessInfo.processInfo.environment
        if env["TERM"] == nil {
            env["TERM"] = "xterm-256color"
        }
        let envKeys = env.map { "\($0.key)=\($0.value)" }
        let cEnv = envKeys.map { $0.withCString { strdup($0) } } + [nil]
        defer { cEnv.forEach { free($0) } }
        
        // Prepare attributes (setsid)
        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        
        // POSIX_SPAWN_SETSID to start new session (like setsid())
        // POSIX_SPAWN_CLOEXEC_DEFAULT to close other fds
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        
        // Change working directory? posix_spawn doesn't support chdir directly on macOS < 10.15 with file actions easily
        // But we can rely on the caller or just execute "cd path && exec" trick if really needed.
        // For now, let's assume we can't easily change CWD without a helper or using a shim shell.
        // A common trick is to spawn "/bin/sh" with "-c" "cd dir && exec tool"
        
        var pid: pid_t = 0
        let spawnResult: Int32
        
        if let workDir = workingDirectory {
            // Use shell shim to handle chdir
            let shimArgs = ["/bin/sh", "-c", "cd \"\(workDir)\" && exec \"\(executable)\" \(arguments.map { "\"\($0)\"" }.joined(separator: " "))"]
            let cShimArgs = shimArgs.map { $0.withCString { strdup($0) } } + [nil]
            defer { cShimArgs.forEach { free($0) } }
            
            spawnResult = posix_spawn(&pid, "/bin/sh", &fileActions, &attrs, cShimArgs, cEnv)
        } else {
            spawnResult = posix_spawn(&pid, executable, &fileActions, &attrs, cArgs, cEnv)
        }
        
        // Close slave in parent
        close(slaveFD)
        
        if spawnResult != 0 {
            close(masterFD)
            throw PTYError.forkFailed // Reuse error code for spawn fail
        }
        
        // Create FileHandle from masterFD
        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        
        return PTYProcess(processID: pid, masterFileHandle: masterHandle)
    }
    
    // Helper for window resize (optional, good for TUI)
    func setWindowSize(fd: Int32, rows: UInt16, cols: UInt16) {
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &winSize)
    }
}

enum PTYError: Error {
    case openPTYFailed
    case forkFailed
}
