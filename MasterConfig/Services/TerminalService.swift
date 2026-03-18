import Foundation
import AppKit

// MARK: - Models

enum PaneSplitDirection: String, Sendable {
    case right  // horizontal split
    case down   // vertical split
}

struct SessionOptions: Sendable {
    var skipPermissions: Bool = true
}

struct TerminalSession: Identifiable, Sendable {
    let id: UUID
    var title: String
    var repoPath: String?
    var processRef: String = ""
    var isRunning: Bool = true
    var isOrphan: Bool = false
    var lastOutput: String = ""
}

// MARK: - Thread-safe output buffer

final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _buffer: String = ""

    var buffer: String {
        lock.lock()
        defer { lock.unlock() }
        return _buffer
    }

    func append(_ text: String) {
        lock.lock()
        _buffer += text
        if _buffer.count > 100_000 {
            _buffer = String(_buffer.suffix(80_000))
        }
        lock.unlock()
    }

    var lastLines: String {
        lock.lock()
        defer { lock.unlock() }
        let lines = _buffer.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(50).joined(separator: "\n")
    }

    var fullOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return _buffer
    }
}

// MARK: - Service

@Observable
@MainActor
final class TerminalService {
    var sessions: [TerminalSession] = []
    var lastError: String? = nil

    // Process tracking (MainActor-only access)
    private var processes: [UUID: Process] = [:]
    private var stdinPipes: [UUID: Pipe] = [:]
    private(set) var outputBuffers: [UUID: OutputBuffer] = [:]

    // MARK: - Session creation (opens iTerm with Claude)

    func newSession(title: String, repoPath: String? = nil, options: SessionOptions = SessionOptions()) {
        lastError = nil
        NSLog("[MasterConfig] newSession called: title=\(title), repoPath=\(repoPath ?? "nil")")

        let claudePath = Self.findClaude()
        guard FileManager.default.fileExists(atPath: claudePath) else {
            lastError = "Claude CLI not found."
            NSLog("[MasterConfig] ERROR: Claude CLI not found")
            return
        }

        var claudeCmd = claudePath
        if options.skipPermissions { claudeCmd += " --dangerously-skip-permissions" }

        let cwd = repoPath ?? NSHomeDirectory()
        let sessionID = UUID()

        // Open iTerm tab with Claude command
        let ok = newITermTab(title: title, command: claudeCmd, cwd: cwd)
        guard ok else {
            NSLog("[MasterConfig] ERROR: Failed to open iTerm tab")
            return
        }

        let session = TerminalSession(
            id: sessionID,
            title: title,
            repoPath: repoPath,
            processRef: "iterm-\(sessionID.uuidString.prefix(8))"
        )
        sessions.append(session)
        NSLog("[MasterConfig] SUCCESS: iTerm session created for \(title)")
    }

    // MARK: - iTerm Integration

    /// Open a new iTerm tab, name the session, and run a command
    func newITermTab(title: String, command: String, cwd: String? = nil) -> Bool {
        let cdPart = cwd.map { "cd \(Self.escapeForAppleScript($0)) && " } ?? ""
        let fullCmd = "\(cdPart)\(command)"
        let safeName = Self.escapeForAppleScript(title)

        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                tell current window
                    create tab with default profile
                end tell
            end if
            tell current window
                tell current session
                    set name to "\(safeName)"
                    write text "\(Self.escapeForAppleScript(fullCmd))"
                end tell
            end tell
        end tell
        """

        return runAppleScript(script, label: "iTerm new tab: \(title)")
    }

    /// Open a new iTerm window, name the session, and run a command
    func newITermWindow(title: String, command: String, cwd: String? = nil) -> Bool {
        let cdPart = cwd.map { "cd \(Self.escapeForAppleScript($0)) && " } ?? ""
        let fullCmd = "\(cdPart)\(command)"
        let safeName = Self.escapeForAppleScript(title)

        let script = """
        tell application "iTerm"
            activate
            create window with default profile
            tell current window
                tell current session
                    set name to "\(safeName)"
                    write text "\(Self.escapeForAppleScript(fullCmd))"
                end tell
            end tell
        end tell
        """

        return runAppleScript(script, label: "iTerm new window: \(title)")
    }

    /// Type text into an iTerm session identified by TTY path
    @discardableResult
    func typeIntoITermByTTY(_ tty: String, text: String) -> Bool {
        let safeText = Self.escapeForAppleScript(text)

        let script = """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell s
                                write text "\(safeText)"
                            end tell
                            return "OK"
                        end if
                    end repeat
                end repeat
            end repeat
            return "NOT FOUND"
        end tell
        """

        return runAppleScript(script, label: "Type into iTerm TTY: \(tty)")
    }

    /// Find the TTY for a given PID
    nonisolated static func ttyForPID(_ pid: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", pid, "-o", "tty="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty, output != "??" else { return nil }
        return "/dev/\(output)"
    }

    /// Type text into a named agent's iTerm session (resolves agent name → PID → TTY)
    /// Falls back to name-based matching if TTY not found
    @discardableResult
    func typeIntoITermSession(named sessionName: String, text: String) -> Bool {
        // This is now a compatibility wrapper — callers should use typeIntoITermByTTY when possible
        let safeText = Self.escapeForAppleScript(text)
        let safeName = Self.escapeForAppleScript(sessionName)

        // Try name-based first (might work if Claude hasn't overridden the name yet)
        let script = """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if name of s contains "\(safeName)" then
                            tell s
                                write text "\(safeText)"
                            end tell
                            return "OK"
                        end if
                    end repeat
                end repeat
            end repeat
            return "NOT FOUND"
        end tell
        """

        return runAppleScript(script, label: "Type into iTerm session: \(sessionName)")
    }

    /// Split the current iTerm pane and run a command
    func splitITermPane(title: String, command: String, cwd: String? = nil, vertical: Bool = true) -> Bool {
        let cdPart = cwd.map { "cd \(Self.escapeForAppleScript($0)) && " } ?? ""
        let fullCmd = "\(cdPart)\(command)"
        let direction = vertical ? "vertically" : "horizontally"

        let script = """
        tell application "iTerm"
            activate
            tell current window
                tell current session
                    split \(direction) with default profile
                end tell
                tell current session
                    write text "\(Self.escapeForAppleScript(fullCmd))"
                end tell
            end tell
        end tell
        """

        return runAppleScript(script, label: "iTerm split \(direction): \(title)")
    }

    /// Open iTerm (plain, no command)
    func openITerm() async {
        let script = """
        tell application "iTerm" to activate
        """
        _ = runAppleScript(script, label: "Open iTerm")
    }

    /// Open a new pane (used by orchestrator for agent visual monitoring)
    func newPane(
        title: String,
        command: String,
        cwd: String? = nil,
        direction: PaneSplitDirection = .right
    ) async -> TerminalSession? {
        lastError = nil

        let vertical = direction == .right
        let ok = splitITermPane(title: title, command: command, cwd: cwd, vertical: vertical)
        guard ok else { return nil }

        let sessionID = UUID()
        let session = TerminalSession(
            id: sessionID,
            title: title,
            repoPath: cwd,
            processRef: "pane-\(sessionID.uuidString.prefix(8))"
        )
        sessions.append(session)
        return session
    }

    // MARK: - AppleScript Helpers

    /// Escape a string for embedding in AppleScript
    nonisolated private static func escapeForAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Run an AppleScript and return success/failure.
    private func runAppleScript(_ source: String, label: String) -> Bool {
        let appleScript = NSAppleScript(source: source)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)

        if let err = errorDict {
            let errNum = err[NSAppleScript.errorNumber] as? Int ?? -1
            let errMsg = err[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let fullErr = "Failed (\(label)): [\(errNum)] \(errMsg)"
            lastError = fullErr
            NSLog("[MasterConfig] AppleScript ERROR: \(fullErr)")
            return false
        }
        return true
    }

    // MARK: - Session lifecycle

    func closeSession(_ sessionID: UUID) {
        if let proc = processes[sessionID], proc.isRunning {
            proc.terminate()
        }
        processes.removeValue(forKey: sessionID)
        stdinPipes.removeValue(forKey: sessionID)
        outputBuffers.removeValue(forKey: sessionID)
        sessions.removeAll { $0.id == sessionID }
    }

    func closeAll() {
        for (_, proc) in processes where proc.isRunning {
            proc.terminate()
        }
        processes.removeAll()
        stdinPipes.removeAll()
        outputBuffers.removeAll()
        sessions.removeAll()
    }

    // MARK: - Status refresh

    func refreshStatus() {
        for i in sessions.indices {
            let id = sessions[i].id
            if let proc = processes[id] {
                sessions[i].isRunning = proc.isRunning
            }
        }
    }

    // MARK: - Read output

    func readScreen(sessionID: UUID) async -> String {
        outputBuffers[sessionID]?.lastLines ?? "(Session running in iTerm)"
    }

    func refreshOutput(sessionID: UUID) async {
        let output = await readScreen(sessionID: sessionID)
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].lastOutput = output
    }

    // MARK: - Send input

    func sendText(_ text: String, sessionID: UUID) {
        guard let pipe = stdinPipes[sessionID],
              let proc = processes[sessionID], proc.isRunning else { return }
        if let data = (text + "\n").data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
    }

    // MARK: - Notifications (no-op)

    func notify(title: String, body: String, sessionID: UUID? = nil) {}

    nonisolated static func sendNotification(title: String, body: String) {}

    // MARK: - Orphan management

    func discoverOrphanSessions() {}

    func killOrphanSession(_ sessionID: UUID) {
        closeSession(sessionID)
    }

    func killAllOrphans() {
        for s in sessions.filter(\.isOrphan) { closeSession(s.id) }
    }

    // MARK: - Claude CLI discovery

    nonisolated static func findClaude() -> String {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        for p in candidates where FileManager.default.fileExists(atPath: p) { return p }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "/usr/local/bin/claude" : out
    }
}

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
