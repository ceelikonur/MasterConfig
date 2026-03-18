import Foundation
import AppKit

// MARK: - Orchestrator Service

@Observable
@MainActor
final class OrchestratorService {
    var state: OrchestratorState? = nil
    var messages: [AgentMessage] = []
    var lastError: String? = nil
    var isRunning: Bool = false

    /// Shared TerminalService — set from MasterConfigApp before use.
    var terminalService: TerminalService?

    private let fm = FileManager.default

    // Watcher process
    private var watcherProcess: Process?

    // MARK: - Directory Paths

    private var baseDir: String {
        NSHomeDirectory() + "/.claude/orchestrator"
    }

    private var stateFilePath: String {
        baseDir + "/state.json"
    }

    private var messagesDir: String {
        baseDir + "/messages"
    }

    // MARK: - Debug

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/mc-orch-debug.log"
        if let data = line.data(using: .utf8) {
            if fm.fileExists(atPath: path) {
                if let fh = FileHandle(forWritingAtPath: path) { fh.seekToEndOfFile(); fh.write(data); fh.closeFile() }
            } else {
                fm.createFile(atPath: path, contents: data)
            }
        }
    }

    // MARK: - Team Lifecycle

    func startTeam(name: String, mode: OrchestratorState.MainSessionMode = .iterm) async {
        lastError = nil
        debugLog("startTeam called: name=\(name), mode=\(mode.rawValue)")

        state = OrchestratorState(
            teamName: name,
            mainSessionMode: mode
        )
        isRunning = true
        ensureDirectories()

        if mode == .iterm {
            // Open lead agent in iTerm
            let launched = await spawnLeadAgentInITerm(teamName: name)
            debugLog("Lead agent iTerm spawn result: \(launched)")

            if !launched {
                lastError = "Failed to open lead agent in iTerm."
            }
        }

        saveState()
        debugLog("startTeam completed. lastError=\(lastError ?? "none")")
    }

    func shutdownTeam() async {
        lastError = nil
        stopWatcher()
        guard var s = state else { return }

        // Kill lead agent by PID
        if let pidStr = s.leadAgentPID, let pid = Int32(pidStr) {
            kill(pid, SIGTERM)
        }

        // Kill all agents by PID
        for agent in s.agents where agent.status != .dead {
            if let pid = Int32(agent.processRef) {
                kill(pid, SIGTERM)
            }
        }

        s.agents.removeAll()
        state = s
        isRunning = false
        saveState()
        cleanupMessages()
    }

    // MARK: - Team Activation

    /// Activate all agents: types the activation prompt into each iTerm session.
    /// Lead agent starts coordinating, sub-agents start polling the task board.
    func activateTeam() async {
        guard let ts = terminalService, let s = state else {
            lastError = "No active team to activate."
            return
        }

        debugLog("activateTeam called — activating \(s.agents.count) agents + lead")

        // Write activation flag
        let flagPath = baseDir + "/active.json"
        let flag: [String: Any] = [
            "active": true,
            "team": s.teamName,
            "activated_at": ISO8601DateFormatter().string(from: Date()),
            "agents": s.agents.map { $0.name }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: flag, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: flagPath))
        }

        // Build agent list for lead agent
        let agentListStr = s.agents.map { "\($0.name) → \($0.repoName) (\($0.repoPath))" }.joined(separator: "\n")

        // Start the file watcher process
        startWatcher()

        // Activate lead agent — SINGLE LINE to avoid Claude Code paste mode
        let leadPrompt = "ACTIVE as lead orchestrator. Team: \(agentListStr.replacingOccurrences(of: "\n", with: ", ")). To assign work use task_post(title, description, assignee, posted_by:\"lead\"). Agents get notified automatically. You'll be notified when tasks complete. Start: call message_read(agent_name:\"lead\") to check for UI tasks, then use task_post to delegate."
        var leadOk = false
        if let pid = state?.leadAgentPID, let tty = TerminalService.ttyForPID(pid) {
            leadOk = ts.typeIntoITermByTTY(tty, text: leadPrompt)
        }
        debugLog("Lead activation: \(leadOk)")

        // Wait a moment between activations to not overwhelm
        try? await Task.sleep(for: .seconds(1))

        // Activate each sub-agent
        for agent in s.agents {
            // SINGLE LINE to avoid Claude Code paste mode
            let agentPrompt = "ACTIVE as agent \"\(agent.name)\" in team \"\(s.teamName)\". Repo: \(agent.repoPath). You will receive task notifications automatically. When you get a task: 1) task_update(task_id:\"<id>\", status:\"in_progress\", updated_by:\"\(agent.name)\") 2) do the work 3) task_update(task_id:\"<id>\", status:\"completed\", result:\"<summary>\", updated_by:\"\(agent.name)\"). Idle now, waiting..."
            var ok = false
            if let tty = TerminalService.ttyForPID(agent.processRef) {
                ok = ts.typeIntoITermByTTY(tty, text: agentPrompt)
            }
            debugLog("Agent \(agent.name) activation: \(ok)")

            try? await Task.sleep(for: .seconds(0.5))
        }

        state?.leadAgentStatus = .working
        saveState()
    }

    // MARK: - Watcher

    /// Start the file watcher that monitors tasks.json and inbox files
    private func startWatcher() {
        stopWatcher()

        let watcherScript = Bundle.main.path(forResource: "task-watcher", ofType: "js")
            ?? NSHomeDirectory() + "/Desktop/pers_projects/MasterConfig/MasterConfig/MCP/task-watcher.js"

        guard fm.fileExists(atPath: watcherScript) else {
            debugLog("Watcher script not found at \(watcherScript)")
            // Fallback: use the known dev path
            let devPath = "/Users/onur/Desktop/pers_projects/MasterConfig/MasterConfig/MCP/task-watcher.js"
            guard fm.fileExists(atPath: devPath) else {
                debugLog("Watcher script not found at dev path either")
                return
            }
            startWatcherProcess(scriptPath: devPath)
            return
        }
        startWatcherProcess(scriptPath: watcherScript)
    }

    private func startWatcherProcess(scriptPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/node")
        proc.arguments = [scriptPath]
        proc.environment = ProcessInfo.processInfo.environment
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle(forWritingAtPath: "/tmp/mc-watcher.log") ?? FileHandle.nullDevice

        do {
            try proc.run()
            watcherProcess = proc
            debugLog("Watcher started: PID \(proc.processIdentifier)")
        } catch {
            debugLog("Failed to start watcher: \(error)")
        }
    }

    private func stopWatcher() {
        if let proc = watcherProcess, proc.isRunning {
            proc.terminate()
            debugLog("Watcher stopped")
        }
        watcherProcess = nil
    }

    // MARK: - Lead Agent

    /// Spawn lead agent in an iTerm window
    private func spawnLeadAgentInITerm(teamName: String) async -> Bool {
        guard let ts = terminalService else {
            lastError = "TerminalService not set."
            return false
        }

        let claudePath = TerminalService.findClaude()
        guard fm.fileExists(atPath: claudePath) else {
            lastError = "Claude CLI not found."
            return false
        }

        let sessionId = state?.sessionId.uuidString ?? UUID().uuidString
        let systemPrompt = buildLeadAgentSystemPrompt(teamName: teamName, sessionId: sessionId)
        let promptFile = NSTemporaryDirectory() + "masterconfig-lead-\(sessionId).md"
        try? systemPrompt.write(toFile: promptFile, atomically: true, encoding: .utf8)

        let claudeCmd = "\(claudePath) --dangerously-skip-permissions --system-prompt \(promptFile.shellEscaped)"

        // Open in iTerm window — session named "mc-lead" for message delivery
        let ok = ts.newITermWindow(title: "mc-lead", command: claudeCmd, cwd: NSHomeDirectory())

        if ok {
            state?.leadAgentStatus = .working

            // Find the PID after a short delay
            Task {
                try? await Task.sleep(for: .seconds(3))
                await self.findLeadAgentPID(promptFile: promptFile)
            }
        }

        return ok
    }

    /// Find lead agent PID by matching the prompt file in process list
    private func findLeadAgentPID(promptFile: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", promptFile]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        if let firstPID = pids.first {
            state?.leadAgentPID = String(firstPID)
            debugLog("Found lead agent PID: \(firstPID)")
            saveState()
        }
    }

    /// System prompt for the lead orchestrator agent
    private func buildLeadAgentSystemPrompt(teamName: String, sessionId: String) -> String {
        // Get current agents for the prompt
        let agentList = (state?.agents ?? []).map { "- \($0.name) (repo: \($0.repoName), path: \($0.repoPath))" }.joined(separator: "\n")

        return """
        # Lead Orchestrator Agent

        You are the lead orchestrator of the "\(teamName)" agent team.
        Your name is: **lead**
        IMPORTANT: Your agent_name for all MCP tool calls is exactly "lead" (not "lead-agent").

        ## Your Team
        \(agentList.isEmpty ? "(No agents spawned yet)" : agentList)

        ## How to Communicate — Use the orchestrator MCP tools

        You have these MCP tools available (orchestrator server):

        ### Assign work to agents:
        `task_post` — Post a task to the shared task board
        - title: short task title
        - description: detailed description
        - assignee: agent name (e.g. "buddy")
        - posted_by: "lead"

        ### Check task progress:
        `task_list` — List all tasks (filter by assignee or status)
        - assignee: filter by agent name
        - status: "pending", "in_progress", "completed", "failed"

        ### Send direct messages:
        `message_send` — Send a message to an agent
        - from: "lead"
        - to: agent name
        - content: your message

        ### Read your inbox:
        `message_read` — Check for messages from agents or UI
        - agent_name: "lead"

        ### See team info:
        `team_info` — Get current team agents and their repos

        ## Your Workflow

        1. When you receive a task, analyze it
        2. Call `team_info` to see available agents and their repos
        3. Break the task into sub-tasks
        4. Use `task_post` to assign each sub-task to the right agent
        5. Periodically call `task_list` to check progress
        6. When all sub-tasks are done, summarize the results

        ## Important
        - Do NOT do implementation work yourself — delegate to agents
        - Each agent works in its own repo — assign tasks to the agent whose repo matches
        - After posting tasks, call `task_list` every ~15 seconds to check for completions
        - Use `message_read(agent_name: "lead")` to check for direct messages from agents
        """
    }

    /// Send a task to the lead agent — types directly into the iTerm session
    func sendTaskToLeadAgent(_ task: String) async {
        let msg = AgentMessage(from: "ui", to: "lead", content: task, messageType: .task)
        messages.append(msg)

        // Write to file for persistence
        ensureAgentMessageDir(agentName: "lead")
        writeMessageToFile(msg, box: "inbox", agentName: "lead")

        // Type into the lead agent's iTerm session via TTY
        if let ts = terminalService, let pid = state?.leadAgentPID,
           let tty = TerminalService.ttyForPID(pid) {
            let delivered = ts.typeIntoITermByTTY(tty, text: task)
            if !delivered {
                lastError = "Could not deliver to lead agent iTerm."
                debugLog("Failed to type into lead TTY \(tty)")
            } else {
                debugLog("Task typed into lead TTY \(tty)")
            }
        } else {
            debugLog("Lead agent PID or TTY not available")
        }

        saveState()
    }

    /// Read lead agent's outbox for responses
    func readLeadAgentOutput() -> String {
        let outboxPath = messagesDir + "/lead-agent/outbox.jsonl"
        guard fm.fileExists(atPath: outboxPath),
              let content = try? String(contentsOfFile: outboxPath, encoding: .utf8) else {
            return ""
        }
        return content
    }

    /// Poll outbox for lead agent messages
    func pollLeadAgentMessages() async -> [AgentMessage] {
        let outboxPath = messagesDir + "/lead-agent/outbox.jsonl"
        guard fm.fileExists(atPath: outboxPath),
              let content = try? String(contentsOfFile: outboxPath, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var newMessages: [AgentMessage] = []
        for line in content.split(separator: "\n") where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let msg = try? decoder.decode(AgentMessage.self, from: data) else { continue }

            if !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
                newMessages.append(msg)
            }
        }

        return newMessages
    }

    // MARK: - Agent Lifecycle

    func spawnAgent(name: String, repoPath: String, task: String?) async -> AgentInstance? {
        lastError = nil

        guard let ts = terminalService else {
            lastError = "TerminalService not set."
            return nil
        }

        let claudePath = TerminalService.findClaude()
        guard fm.fileExists(atPath: claudePath) else {
            lastError = "Claude CLI not found."
            return nil
        }

        var agent = AgentInstance(
            name: name,
            repoPath: repoPath,
            currentTask: task
        )

        ensureAgentMessageDir(agentName: name)

        let systemPrompt = buildAgentSystemPrompt(agent: agent, task: task)
        let promptFile = NSTemporaryDirectory() + "masterconfig-agent-\(agent.id.uuidString).md"
        try? systemPrompt.write(toFile: promptFile, atomically: true, encoding: .utf8)

        // Build command
        var claudeCmd = "\(claudePath) --dangerously-skip-permissions --system-prompt \(promptFile.shellEscaped)"
        if let task = task, !task.isEmpty {
            claudeCmd += " -p \(task.shellEscaped)"
        }

        // Open in iTerm tab — session named "mc-<name>" for message delivery
        let ok = ts.newITermTab(title: "mc-\(name)", command: claudeCmd, cwd: repoPath)

        guard ok else {
            lastError = "Failed to open iTerm tab for agent '\(name)'."
            return nil
        }

        agent.status = .working

        // Find PID after short delay
        let agentId = agent.id
        let pFile = promptFile
        Task {
            try? await Task.sleep(for: .seconds(3))
            await self.findAgentPID(agentId: agentId, promptFile: pFile)
        }

        state?.agents.append(agent)
        saveState()

        debugLog("Agent \(name) opened in iTerm tab")
        return agent
    }

    /// Find agent PID by matching the prompt file in process list
    private func findAgentPID(agentId: UUID, promptFile: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", promptFile]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        if let firstPID = pids.first {
            if var s = state, let idx = s.agents.firstIndex(where: { $0.id == agentId }) {
                s.agents[idx].processRef = String(firstPID)
                state = s
                debugLog("Found agent PID: \(firstPID)")
                saveState()
            }
        }
    }

    func killAgent(_ agentID: UUID) async {
        guard var s = state, let idx = s.agents.firstIndex(where: { $0.id == agentID }) else { return }
        if let pid = Int32(s.agents[idx].processRef) {
            kill(pid, SIGTERM)
        }
        s.agents[idx].status = .dead
        s.agents[idx].lastActivity = Date()
        state = s
        saveState()
    }

    func removeAgent(_ agentID: UUID) {
        guard var s = state, let idx = s.agents.firstIndex(where: { $0.id == agentID }) else { return }
        if s.agents[idx].status != .dead {
            if let pid = Int32(s.agents[idx].processRef) {
                kill(pid, SIGTERM)
            }
        }
        s.agents.remove(at: idx)
        state = s
        saveState()
    }

    // MARK: - Status Refresh

    func refreshAllStatus() async {
        guard var s = state else { return }

        // Check lead agent PID
        if let pidStr = s.leadAgentPID, let pid = Int32(pidStr) {
            let alive = kill(pid, 0) == 0
            s.leadAgentStatus = alive ? .working : .dead
        }

        // Check all agents by PID
        for i in s.agents.indices {
            if !s.agents[i].processRef.isEmpty, let pid = Int32(s.agents[i].processRef) {
                let alive = kill(pid, 0) == 0
                if alive {
                    if s.agents[i].status == .starting || s.agents[i].status == .dead {
                        s.agents[i].status = .working
                    }
                    s.agents[i].lastActivity = Date()
                } else {
                    if s.agents[i].status != .completed {
                        s.agents[i].status = .dead
                    }
                }
            } else if s.agents[i].status == .starting {
                // PID not found yet — might still be starting
                let elapsed = Date().timeIntervalSince(s.agents[i].spawnedAt)
                if elapsed > 30 {
                    s.agents[i].status = .dead
                }
            }
        }

        state = s
        saveState()
    }

    func getAgentOutput(_ agentID: UUID) async -> String {
        guard let agent = state?.agents.first(where: { $0.id == agentID }) else {
            return "(Agent not found)"
        }

        // Read agent's outbox
        let outboxPath = messagesDir + "/\(agent.name)/outbox.jsonl"
        if fm.fileExists(atPath: outboxPath),
           let content = try? String(contentsOfFile: outboxPath, encoding: .utf8),
           !content.isEmpty {
            return content
        }

        return "(No output yet. Agent is running in iTerm — check the iTerm window.)"
    }

    // MARK: - Messaging

    func sendMessage(from: String, to: String, content: String, type: AgentMessage.MessageType) async {
        let message = AgentMessage(from: from, to: to, content: content, messageType: type)
        messages.append(message)

        // Write to file-based inbox
        ensureAgentMessageDir(agentName: to)
        writeMessageToFile(message, box: "inbox", agentName: to)

        // Also type into the agent's iTerm session via TTY
        if let ts = terminalService {
            let pid = to == "lead" ? state?.leadAgentPID : state?.agents.first(where: { $0.name == to })?.processRef
            if let pid = pid, let tty = TerminalService.ttyForPID(pid) {
                ts.typeIntoITermByTTY(tty, text: content)
            }
        }

        if var s = state, let idx = s.agents.firstIndex(where: { $0.name == to }) {
            s.agents[idx].messageCount += 1
            s.agents[idx].lastActivity = Date()
            state = s
        }

        saveState()
    }

    func broadcastMessage(from: String, content: String) async {
        guard let s = state else { return }
        for agent in s.agents where agent.status != .dead {
            await sendMessage(from: from, to: agent.name, content: content, type: .context)
        }
    }

    func loadMessages() async {
        loadFileMessages()
        _ = await pollLeadAgentMessages()
    }

    private func loadFileMessages() {
        guard fm.fileExists(atPath: messagesDir) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var fileMessages: [AgentMessage] = []
        guard let agentDirs = try? fm.contentsOfDirectory(atPath: messagesDir) else { return }
        for agentDir in agentDirs {
            for box in ["inbox", "outbox"] {
                let boxPath = messagesDir + "/\(agentDir)/\(box).jsonl"
                guard fm.fileExists(atPath: boxPath),
                      let content = try? String(contentsOfFile: boxPath, encoding: .utf8) else { continue }

                for line in content.split(separator: "\n") where !line.isEmpty {
                    if let data = line.data(using: .utf8),
                       let msg = try? decoder.decode(AgentMessage.self, from: data) {
                        fileMessages.append(msg)
                    }
                }
            }
        }

        // Merge avoiding duplicates
        for msg in fileMessages {
            if !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
            }
        }

        messages.sort { $0.timestamp < $1.timestamp }
    }

    func pollMessages(for agentName: String) -> [AgentMessage] {
        let inboxPath = messagesDir + "/\(agentName)/inbox.jsonl"
        guard fm.fileExists(atPath: inboxPath),
              let content = try? String(contentsOfFile: inboxPath, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [AgentMessage] = []
        for line in content.split(separator: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let msg = try? decoder.decode(AgentMessage.self, from: data) {
                result.append(msg)
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Reconnect

    func reconnectOrphans() async {
        guard loadState(), var s = state else { return }

        // Check lead agent PID
        if let pidStr = s.leadAgentPID, let pid = Int32(pidStr) {
            let alive = kill(pid, 0) == 0
            s.leadAgentStatus = alive ? .working : .dead
        } else {
            s.leadAgentStatus = .dead
        }

        // Check agent PIDs
        for i in s.agents.indices {
            if let pid = Int32(s.agents[i].processRef) {
                let alive = kill(pid, 0) == 0
                if alive {
                    if s.agents[i].status == .dead { s.agents[i].status = .idle }
                } else {
                    if s.agents[i].status != .completed {
                        s.agents[i].status = .dead
                    }
                }
            } else {
                if s.agents[i].status != .completed {
                    s.agents[i].status = .dead
                }
            }
        }

        state = s
        isRunning = s.agents.contains { $0.status != .dead && $0.status != .completed }
            || s.leadAgentStatus == .working
        saveState()
        await loadMessages()
    }

    func resumeTeam() async {
        await reconnectOrphans()
    }

    // MARK: - Open iTerm

    func openITerm() async {
        await terminalService?.openITerm()
    }

    // MARK: - Persistence

    @discardableResult
    func loadState() -> Bool {
        guard fm.fileExists(atPath: stateFilePath) else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
              let loaded = try? decoder.decode(OrchestratorState.self, from: data) else {
            lastError = "Failed to decode orchestrator state from \(stateFilePath)"
            return false
        }

        state = loaded
        isRunning = loaded.agents.contains { $0.status != .dead && $0.status != .completed }
            || loaded.leadAgentStatus == .working
        return true
    }

    func saveState() {
        ensureDirectories()
        guard var s = state else { return }

        s.lastSaved = Date()
        state = s

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(s) else {
            lastError = "Failed to encode orchestrator state"
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
        } catch {
            lastError = "Failed to write orchestrator state: \(error.localizedDescription)"
        }
    }

    // MARK: - System Prompt Builder

    private func buildAgentSystemPrompt(agent: AgentInstance, task: String?) -> String {
        let teamName = state?.teamName ?? "default"

        var prompt = """
        # Agent: \(agent.name)

        You are a team member in the "\(teamName)" team.
        Your name is: **\(agent.name)**
        Your repo: \(agent.repoPath)

        ## How to Communicate — Use the orchestrator MCP tools

        ### Check for assigned tasks:
        `task_list` — Call with assignee: "\(agent.name)" to see tasks assigned to you
        - Call this FIRST when you start, and periodically after

        ### Update task status:
        `task_update` — Update a task's status
        - task_id: the task ID
        - status: "in_progress" when you start, "completed" when done, "failed" if stuck
        - result: your result summary
        - updated_by: "\(agent.name)"

        ### Read messages:
        `message_read` — Check your inbox for messages
        - agent_name: "\(agent.name)"

        ### Send messages:
        `message_send` — Send a message to another agent or lead
        - from: "\(agent.name)"
        - to: recipient name (e.g. "lead")
        - content: your message

        ### See team info:
        `team_info` — See all agents and their repos

        ## Your Workflow

        1. Call `task_list(assignee: "\(agent.name)")` to check for tasks
        2. When you find a pending task, call `task_update(task_id, status: "in_progress", updated_by: "\(agent.name)")`
        3. Do the work in your repo
        4. When done, call `task_update(task_id, status: "completed", result: "<summary>", updated_by: "\(agent.name)")`
        5. Check for more tasks

        ## Guidelines
        - Stay focused on your assigned repo
        - Do NOT modify files outside \(agent.repoPath)
        - Always update task status so the lead agent knows your progress
        """

        if let task = task, !task.isEmpty {
            prompt += """


            ## Initial Task
            \(task)
            """
        }

        return prompt
    }

    // MARK: - File Helpers

    private func writeMessageToFile(_ msg: AgentMessage, box: String, agentName: String) {
        let filePath = messagesDir + "/\(agentName)/\(box).jsonl"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(msg),
              let line = String(data: data, encoding: .utf8) else { return }
        let appendLine = line + "\n"

        if fm.fileExists(atPath: filePath) {
            if let handle = FileHandle(forWritingAtPath: filePath) {
                handle.seekToEndOfFile()
                if let lineData = appendLine.data(using: .utf8) {
                    handle.write(lineData)
                }
                handle.closeFile()
            }
        } else {
            try? appendLine.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }

    private func ensureDirectories() {
        try? fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: messagesDir, withIntermediateDirectories: true)
    }

    private func ensureAgentMessageDir(agentName: String) {
        let agentDir = messagesDir + "/\(agentName)"
        try? fm.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
    }

    private func cleanupMessages() {
        _ = try? fm.removeItem(atPath: messagesDir)
        _ = try? fm.createDirectory(atPath: messagesDir, withIntermediateDirectories: true)
    }
}

// MARK: - String Shell Escaping

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
