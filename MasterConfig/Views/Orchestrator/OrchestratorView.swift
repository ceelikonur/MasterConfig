import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let statusGreen = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let statusBlue = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let statusGray = Color(red: 0.34, green: 0.37, blue: 0.54)
    static let statusRed = Color(red: 0.97, green: 0.47, blue: 0.56)
    static let statusOrange = Color(red: 0.95, green: 0.68, blue: 0.32)
}

// MARK: - OrchestratorView

struct OrchestratorView: View {
    @Environment(OrchestratorService.self) private var orchestrator
    @Environment(RepoService.self) private var repoService

    @State private var selectedAgentID: UUID?
    @State private var showNewTeamSheet = false
    @State private var showAddAgentSheet = false
    @State private var showShutdownConfirm = false
    @State private var statusTimer: Timer?
    @State private var messageTimer: Timer?
    @State private var taskInput: String = ""
    @State private var isSendingTask = false

    var body: some View {
        HSplitView {
            agentSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            mainContent
                .frame(minWidth: 500)
        }
        .background(Color.bgPrimary)
        .navigationTitle("Orchestrator")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showNewTeamSheet = true
                } label: {
                    Label("New Team", systemImage: "person.3.fill")
                }
                .help("Create a new agent team")

                Button {
                    showAddAgentSheet = true
                } label: {
                    Label("Add Agent", systemImage: "plus.circle")
                }
                .help("Spawn a new agent")
                .disabled(!orchestrator.isRunning)

                Button {
                    Task { await orchestrator.activateTeam() }
                } label: {
                    Label("Activate", systemImage: "bolt.fill")
                }
                .help("Activate all agents — start task board polling")
                .disabled(!orchestrator.isRunning || (orchestrator.state?.agents.isEmpty ?? true))

                Button(role: .destructive) {
                    showShutdownConfirm = true
                } label: {
                    Label("Shutdown", systemImage: "power")
                }
                .help("Shutdown all agents")
                .disabled(!orchestrator.isRunning)
            }
        }
        .sheet(isPresented: $showNewTeamSheet) {
            NewTeamSheet { name, mode in
                Task {
                    await orchestrator.startTeam(name: name, mode: mode)
                    showNewTeamSheet = false
                }
            }
        }
        .sheet(isPresented: $showAddAgentSheet) {
            AddAgentSheet(repos: repoService.repos) { name, repoPath, task in
                Task {
                    await orchestrator.spawnAgent(name: name, repoPath: repoPath, task: task)
                }
                showAddAgentSheet = false
            }
        }
        .alert("Shutdown Team", isPresented: $showShutdownConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Shutdown", role: .destructive) {
                Task { await orchestrator.shutdownTeam() }
            }
        } message: {
            Text("This will kill all agents and end the orchestrator session. Are you sure?")
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Agent Sidebar

    private var agentSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if orchestrator.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.statusGreen)
                            .frame(width: 7, height: 7)
                        Text("Live")
                            .font(.caption2)
                            .foregroundStyle(Color.statusGreen)
                    }
                }
            }
            .padding(12)

            Divider()

            if let state = orchestrator.state {
                // Team info
                HStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accent)
                    Text(state.teamName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(state.mainSessionMode.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accent.opacity(0.15))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Main session entry
                Button {
                    selectedAgentID = nil
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(orchestrator.isRunning ? Color.statusGreen : Color.statusGray)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("orchestrator")
                                .font(.system(.body, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("main session")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedAgentID == nil ? Color.accent.opacity(0.12) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.top, 4)

                if !state.agents.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.textSecondary.opacity(0.3))
                            .frame(height: 1)
                        Text("team")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                        Rectangle()
                            .fill(Color.textSecondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                // Agent list
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.agents) { agent in
                            agentRow(agent)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            } else {
                // No active team
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.3")
                        .font(.title)
                        .foregroundStyle(Color.textSecondary)
                    Text("No active team")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Button("New Team") {
                        showNewTeamSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.bgPrimary)
    }

    private func agentRow(_ agent: AgentInstance) -> some View {
        Button {
            selectedAgentID = agent.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: agent.status))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(agent.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                if agent.messageCount > 0 {
                    Text("\(agent.messageCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accent.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectedAgentID == agent.id ? Color.accent.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if orchestrator.state != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mainTerminalSection
                        agentCardsSection
                        messageLogSection
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Main Terminal Section

    private var mainTerminalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(Color.accent)
                Text("Main Session")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if let state = orchestrator.state {
                    Text(state.mainSessionMode == .embedded ? "Embedded" : "iTerm")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accent.opacity(0.12))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(4)
                }
            }

            if let state = orchestrator.state {
                VStack(spacing: 12) {
                    if state.mainSessionMode == .embedded {
                        EmbeddedTerminalView(
                            repoPath: nil,
                            skipPermissions: true
                        )
                        .frame(height: 300)
                        .cornerRadius(8)
                    } else {
                        // iTerm mode — lead agent + task input
                        leadAgentSection
                    }

                    // Session metadata
                    HStack(spacing: 16) {
                        Label("Session: \(state.sessionId.uuidString.prefix(8))...",
                              systemImage: "number")
                        Label("Created: \(state.createdAt.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "clock")
                        Label("Agents: \(state.agents.count)",
                              systemImage: "person.2")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(10)
    }

    // MARK: - Lead Agent Section (iTerm mode)

    private var leadAgentSection: some View {
        VStack(spacing: 12) {
            // Error banner
            if let error = orchestrator.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Dismiss") {
                        orchestrator.lastError = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Lead agent status bar
            HStack(spacing: 8) {
                Circle()
                    .fill(leadAgentStatusColor)
                    .frame(width: 8, height: 8)
                Text("Lead Agent")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                if let status = orchestrator.state?.leadAgentStatus {
                    Text(status.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(leadAgentStatusColor.opacity(0.15))
                        .foregroundStyle(leadAgentStatusColor)
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    Task { await orchestrator.openITerm() }
                } label: {
                    Label("Open iTerm", systemImage: "terminal.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            // Lead agent message feed
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        let leadMessages = orchestrator.messages.filter {
                            $0.from == "lead-agent" || $0.to == "lead-agent"
                        }
                        if leadMessages.isEmpty {
                            Text("Lead agent starting...")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .padding(8)
                        }
                        ForEach(leadMessages) { msg in
                            leadAgentMessageRow(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: orchestrator.messages.count) { _, _ in
                    let leadMsgs = orchestrator.messages.filter {
                        $0.from == "lead-agent" || $0.to == "lead-agent"
                    }
                    if let last = leadMsgs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(height: 180)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            .cornerRadius(6)

            // Task input
            HStack(spacing: 8) {
                TextField("Send a task to the lead agent...", text: $taskInput)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(8)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
                    .cornerRadius(6)
                    .onSubmit { sendTask() }

                Button {
                    sendTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(taskInput.isEmpty ? Color.textSecondary : Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(taskInput.isEmpty || isSendingTask)
            }
        }
        .cornerRadius(8)
    }

    private func leadAgentMessageRow(_ msg: AgentMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: msg.from == "lead-agent" ? "cpu" : "person.fill")
                .font(.caption2)
                .foregroundStyle(msg.from == "lead-agent" ? Color.accent : Color.statusGreen)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(msg.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)

                Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var leadAgentStatusColor: Color {
        switch orchestrator.state?.leadAgentStatus {
        case .working: return .statusBlue
        case .idle: return .statusGreen
        case .starting: return .statusGray
        case .dead: return .statusRed
        case .completed: return .statusGreen
        default: return .statusGray
        }
    }

    private func sendTask() {
        let task = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        isSendingTask = true
        taskInput = ""
        Task {
            await orchestrator.sendTaskToLeadAgent(task)
            isSendingTask = false
        }
    }

    // MARK: - Agent Cards Section

    private var agentCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color.accent)
                Text("Agents")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                if let state = orchestrator.state {
                    Text("\(state.agents.count)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Button {
                    showAddAgentSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!orchestrator.isRunning)
            }

            if let state = orchestrator.state, !state.agents.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(state.agents) { agent in
                        AgentCardView(agent: agent) {
                            Task { await orchestrator.killAgent(agent.id) }
                        } onReadOutput: {
                            await orchestrator.getAgentOutput(agent.id)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Color.textSecondary)
                    Text("No agents spawned yet. Add an agent to get started.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(16)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(10)
    }

    // MARK: - Message Log Section

    private var messageLogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MessageLogView(messages: orchestrator.messages)
                .frame(minHeight: 200, idealHeight: 300)
        }
        .background(Color.surface)
        .cornerRadius(10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("No Active Orchestrator Session")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Create a team to start orchestrating agents.\nAgents run as managed processes and coordinate through messages.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showNewTeamSheet = true
            } label: {
                Label("New Team", systemImage: "person.3.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func statusColor(for status: AgentStatus) -> Color {
        switch status {
        case .starting: return .statusGray
        case .idle: return .statusGreen
        case .working: return .statusBlue
        case .blocked: return .statusOrange
        case .completed: return .statusGreen
        case .dead: return .statusRed
        case .orphan: return .statusOrange
        }
    }

    private func startPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                await orchestrator.refreshAllStatus()
            }
        }
        messageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                await orchestrator.loadMessages()
            }
        }
    }

    private func stopPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
        messageTimer?.invalidate()
        messageTimer = nil
    }
}

// MARK: - New Team Sheet

struct NewTeamSheet: View {
    let onCreate: (String, OrchestratorState.MainSessionMode) -> Void

    @State private var teamName = ""
    @State private var mode: OrchestratorState.MainSessionMode = .iterm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color.accent)
                Text("New Agent Team")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Team") {
                    TextField("Team Name", text: $teamName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Main Session Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(OrchestratorState.MainSessionMode.allCases, id: \.self) { m in
                            Text(m.rawValue.capitalized).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .embedded:
                        Text("Runs the orchestrator's Claude CLI directly inside MasterConfig with piped I/O.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    case .iterm:
                        Text("Agents run as managed processes. Open iTerm for full terminal access.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Create Team") {
                    let name = teamName.isEmpty ? "Team-\(Date().formatted(.dateTime.hour().minute()))" : teamName
                    onCreate(name, mode)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(teamName.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 340)
    }
}

// MARK: - Add Agent Sheet

struct AddAgentSheet: View {
    let repos: [Repo]
    let onAdd: (String, String, String?) -> Void

    @State private var agentName = ""
    @State private var selectedRepo: Repo?
    @State private var taskDescription = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accent)
                Text("Add Agent")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Agent") {
                    TextField("Agent Name", text: $agentName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Repository") {
                    Picker("Repository", selection: $selectedRepo) {
                        Text("-- Select --").tag(Optional<Repo>.none)
                        ForEach(repos) { repo in
                            Text(repo.name).tag(Optional(repo))
                        }
                    }

                    if let repo = selectedRepo {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.textSecondary)
                                .font(.caption)
                            Text(repo.path)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }

                Section("Initial Task (optional)") {
                    TextEditor(text: $taskDescription)
                        .font(.body)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color.bgPrimary.opacity(0.5))
                        .cornerRadius(6)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Spawn Agent") {
                    guard let repo = selectedRepo else { return }
                    let task = taskDescription.isEmpty ? nil : taskDescription
                    onAdd(agentName, repo.path, task)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(agentName.isEmpty || selectedRepo == nil)
            }
            .padding()
        }
        .frame(width: 440, height: 460)
    }
}
