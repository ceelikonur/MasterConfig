import Foundation

// MARK: - Models

struct SessionOptions: Sendable {
    var skipPermissions: Bool = true
}

struct TerminalSession: Identifiable, Sendable {
    let id: UUID
    var title: String
    var repoPath: String?
    var tmuxName: String
    var isRunning: Bool = true
    var isOrphan: Bool = false
}

// MARK: - Service

@Observable
@MainActor
final class TerminalService {
    var sessions: [TerminalSession] = []
    var lastError: String? = nil

    // MARK: - Session creation

    func newSession(title: String, repoPath: String? = nil, options: SessionOptions = SessionOptions()) {
        lastError = nil

        let claudePath = Self.findClaude()
        guard FileManager.default.fileExists(atPath: claudePath) else {
            lastError = "Claude CLI not found. Searched ~/.local/bin, /opt/homebrew/bin, /usr/local/bin."
            return
        }

        guard let tmuxPath = Self.findBinary("tmux", extraPaths: ["/opt/homebrew/bin/tmux"]) else {
            lastError = "tmux not found. Install with: brew install tmux"
            return
        }

        let sessionID = UUID()
        let sessionName = "mc-\(sessionID.uuidString.prefix(8))"
        let cwd = repoPath ?? NSHomeDirectory()

        // Build the command to run inside tmux
        var claudeCmd = claudePath
        if options.skipPermissions { claudeCmd += " --dangerously-skip-permissions" }

        let shellCmd = [
            "export TERM=xterm-256color",
            "export COLORTERM=truecolor",
            "export LANG=en_US.UTF-8",
            "unset CLAUDECODE",
            "exec \(claudeCmd)",
        ].joined(separator: "; ")

        // Create detached tmux session
        Self.runTmuxCommand(tmuxPath, args: [
            "new-session", "-d", "-s", sessionName, "-c", cwd, shellCmd
        ])

        // Set tmux options
        Self.runTmuxCommand(tmuxPath, args: ["set-option", "-t", sessionName, "mouse", "on"])
        Self.runTmuxCommand(tmuxPath, args: ["set-option", "-t", sessionName, "status", "off"])
        Self.runTmuxCommand(tmuxPath, args: ["set-option", "-s", "escape-time", "0"])
        Self.runTmuxCommand(tmuxPath, args: ["set-option", "-t", sessionName, "history-limit", "50000"])

        // Verify session was created
        let existing = Self.listMcTmuxSessions()
        guard existing.contains(where: { $0.name == sessionName }) else {
            lastError = "Failed to create tmux session '\(sessionName)'"
            return
        }

        sessions.append(TerminalSession(
            id: sessionID,
            title: title,
            repoPath: repoPath,
            tmuxName: sessionName
        ))

        // Open in Terminal.app
        openInTerminal(sessionName: sessionName)
    }

    // MARK: - Terminal.app integration

    func openInTerminal(sessionName: String) {
        guard let tmuxPath = Self.findBinary("tmux", extraPaths: ["/opt/homebrew/bin/tmux"]) else {
            lastError = "tmux not found"
            return
        }

        let script = """
        tell application "Terminal"
            activate
            do script "\(tmuxPath) attach-session -t \(sessionName)"
        end tell
        """

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    // MARK: - Session lifecycle

    func closeSession(_ sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        Self.killTmuxSession(sessions[idx].tmuxName)
        sessions.remove(at: idx)
    }

    func closeAll() {
        for s in sessions {
            Self.killTmuxSession(s.tmuxName)
        }
        sessions.removeAll()
    }

    // MARK: - Status refresh

    func refreshStatus() {
        let activeNames = Set(Self.listMcTmuxSessions().map(\.name))
        for i in sessions.indices {
            sessions[i].isRunning = activeNames.contains(sessions[i].tmuxName)
        }
        // Clean up dead sessions (keep orphans for user to dismiss)
        sessions.removeAll { !$0.isRunning && !$0.isOrphan }
    }

    // MARK: - Orphan tmux session management

    func discoverOrphanSessions() {
        let found = Self.listMcTmuxSessions()
        let knownNames = Set(sessions.map(\.tmuxName))
        for entry in found where !knownNames.contains(entry.name) {
            sessions.append(TerminalSession(
                id: UUID(), title: entry.name,
                tmuxName: entry.name, isOrphan: true
            ))
        }
    }

    func attachToOrphan(_ sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID && $0.isOrphan }) else { return }
        guard let tmuxPath = Self.findBinary("tmux", extraPaths: ["/opt/homebrew/bin/tmux"]) else {
            lastError = "tmux not found"; return
        }

        let tmuxName = sessions[idx].tmuxName

        // Re-apply tmux settings
        Task.detached {
            Self.runTmuxCommand(tmuxPath, args: ["set-option", "-t", tmuxName, "mouse", "on"])
            Self.runTmuxCommand(tmuxPath, args: ["set-option", "-t", tmuxName, "status", "off"])
            Self.runTmuxCommand(tmuxPath, args: ["set-option", "-s", "escape-time", "0"])
        }

        sessions[idx].isOrphan = false
        openInTerminal(sessionName: tmuxName)
    }

    func killOrphanSession(_ sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        Self.killTmuxSession(sessions[idx].tmuxName)
        sessions.remove(at: idx)
    }

    func killAllOrphans() {
        for s in sessions.filter(\.isOrphan) {
            Self.killTmuxSession(s.tmuxName)
        }
        sessions.removeAll(where: \.isOrphan)
    }

    // MARK: - Helpers

    private nonisolated static func findClaude() -> String {
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
        proc.standardError  = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "/usr/local/bin/claude" : out
    }

    private nonisolated static func findBinary(_ name: String, extraPaths: [String] = []) -> String? {
        let paths = extraPaths + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        for p in paths where FileManager.default.fileExists(atPath: p) { return p }
        return nil
    }

    // MARK: - tmux helpers

    private struct TmuxEntry { let name: String }

    private nonisolated static func listMcTmuxSessions() -> [TmuxEntry] {
        guard let tmux = findBinary("tmux", extraPaths: ["/opt/homebrew/bin/tmux"]) else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").compactMap { line in
            let name = String(line)
            guard name.hasPrefix("mc-") else { return nil }
            return TmuxEntry(name: name)
        }
    }

    nonisolated static func runTmuxCommand(_ tmuxPath: String, args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    private nonisolated static func killTmuxSession(_ name: String) {
        guard let tmux = findBinary("tmux", extraPaths: ["/opt/homebrew/bin/tmux"]) else { return }
        runTmuxCommand(tmux, args: ["kill-session", "-t", name])
    }
}
