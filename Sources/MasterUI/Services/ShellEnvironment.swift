import Foundation

/// Captures the user's interactive-login-shell environment so that processes
/// spawned from this menu-bar app inherit the same PATH, NVM_DIR, GOPATH, etc.
/// that a normal Terminal.app session would see.
///
/// macOS menu-bar apps inherit only the minimal launchd environment
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), missing Homebrew, NVM, pyenv, Cargo, etc.
/// This utility runs the user's shell once at startup, caches the result, and
/// provides it to all process-spawning call sites.
enum ShellEnvironment {

    /// Full environment dictionary resolved from the user's login shell.
    /// Falls back to the process environment with an enriched PATH if
    /// the shell capture fails.
    static let resolved: [String: String] = {
        if let captured = captureFromLoginShell() {
            return captured
        }
        print("[ShellEnvironment] Using fallback enriched PATH")
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedFallbackPath(existing: env["PATH"])
        return env
    }()

    // MARK: - Shell Capture

    private static func captureFromLoginShell() -> [String: String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -i: interactive  → sources .zshrc / .bashrc  (where nvm/pyenv/rbenv live)
        // -l: login        → sources .zprofile / .bash_profile
        // -c: run command then exit
        process.arguments = ["-ilc", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = FileHandle.nullDevice
        // Prevent the child shell from reading stdin (avoids hangs on `read` calls)
        process.standardInput  = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[ShellEnvironment] Failed to launch \(shell): \(error)")
            return nil
        }

        // Read output and wait with a 5-second timeout to avoid hanging forever
        // if the user's shell init blocks on something.
        var data = Data()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            sem.signal()
        }

        if sem.wait(timeout: .now() + .seconds(5)) == .timedOut {
            process.terminate()
            print("[ShellEnvironment] Shell timed out after 5s, using fallback")
            return nil
        }

        guard process.terminationStatus == 0 else {
            print("[ShellEnvironment] Shell exited with status \(process.terminationStatus)")
            return nil
        }

        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse KEY=VALUE lines. Filter by valid env-var key pattern to skip
        // noise that .zshrc might print to stdout (e.g. echo "Welcome!").
        var env: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let eqRange = line.range(of: "=") else { continue }
            let key = String(line[line.startIndex..<eqRange.lowerBound])
            guard !key.isEmpty,
                  key.first!.isLetter || key.first == "_",
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { continue }
            let value = String(line[eqRange.upperBound...])
            env[key] = value
        }

        // Sanity check: must have PATH at minimum
        guard env["PATH"] != nil else {
            print("[ShellEnvironment] Captured env missing PATH, discarding")
            return nil
        }

        print("[ShellEnvironment] Captured \(env.count) variables from \(shell)")
        return env
    }

    // MARK: - Fallback

    /// Hardcoded PATH enrichment for when shell capture fails.
    /// Scans common directories so that tools installed via Homebrew, NVM, etc.
    /// can still be found.
    private static func enrichedFallbackPath(existing: String?) -> String {
        let home = NSHomeDirectory()
        var extra = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
        ]

        // NVM node versions (newest first)
        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted(by: >) {
                extra.append("\(nvmBase)/\(v)/bin")
            }
        }

        // Python user-local bins
        let pyBase = "\(home)/Library/Python"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: pyBase) {
            for v in versions.sorted(by: >) {
                extra.append("\(pyBase)/\(v)/bin")
            }
        }

        let base = existing ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let baseParts = Set(base.components(separatedBy: ":"))
        let newParts = extra.filter { !baseParts.contains($0) }
        return (newParts + [base]).joined(separator: ":")
    }
}
