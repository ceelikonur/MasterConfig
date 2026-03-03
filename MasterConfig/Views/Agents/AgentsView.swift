import SwiftUI

struct AgentsView: View {
    @Environment(ClaudeService.self) private var claudeService
    @State private var selectedAgent: Agent?
    @State private var searchText = ""
    @State private var editorContent = ""
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private enum SaveStatus {
        case idle, saving, saved
    }

    private var filteredAgents: [Agent] {
        if searchText.isEmpty { return claudeService.agents }
        let q = searchText.lowercased()
        return claudeService.agents.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) || $0.model.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            agentList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            detailPanel
                .frame(minWidth: 400)
        }
        .task { await claudeService.loadAgents() }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Delete Agent", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(selectedAgent?.name ?? "")\"? This cannot be undone.")
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet { newAgent in
                createAgent(newAgent)
            }
        }
    }

    // MARK: - Agent List

    private var agentList: some View {
        VStack(spacing: 0) {
            searchField
            if filteredAgents.isEmpty {
                emptyListPlaceholder
            } else {
                List(filteredAgents, selection: $selectedAgent) { agent in
                    AgentRow(agent: agent)
                        .tag(agent)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                Button {
                    if selectedAgent != nil { showDeleteAlert = true }
                } label: {
                    Label("Delete Agent", systemImage: "minus")
                }
                .disabled(selectedAgent == nil)
            }
        }
        .onChange(of: selectedAgent) { _, newValue in
            editorContent = newValue?.content ?? ""
            saveStatus = .idle
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            TextField("Filter agents...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
        }
        .padding(8)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    private var emptyListPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            Text("No agents found")
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            if searchText.isEmpty {
                Text("Click + to create a new agent")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let agent = selectedAgent {
                VStack(spacing: 0) {
                    WebEditorView(
                        content: $editorContent,
                        language: "markdown",
                        isReadOnly: false,
                        onSave: { saveCurrentAgent() }
                    )
                    toolsBar(for: agent)
                    statusBar(for: agent)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("Select an agent to edit")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.1, green: 0.11, blue: 0.15))
            }
        }
    }

    private func toolsBar(for agent: Agent) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if agent.tools.isEmpty {
                    Text("No tools configured")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                } else {
                    ForEach(agent.tools, id: \.self) { tool in
                        Text(tool)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.2))
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(red: 0.13, green: 0.14, blue: 0.18).opacity(0.7))
    }

    private func statusBar(for agent: Agent) -> some View {
        HStack {
            Text(agent.filePath)
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            switch saveStatus {
            case .idle:
                EmptyView()
            case .saving:
                ProgressView()
                    .controlSize(.small)
                Text("Saving...")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Button("Save") { saveCurrentAgent() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Actions

    private func saveCurrentAgent() {
        guard var agent = selectedAgent else { return }
        agent.content = editorContent
        let fm = claudeService.parseFrontmatter(editorContent)
        if let name = fm["name"], !name.isEmpty { agent.name = name }
        if let desc = fm["description"] { agent.description = desc }
        if let model = fm["model"], !model.isEmpty { agent.model = model }
        if let toolsStr = fm["tools"] {
            agent.tools = toolsStr
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        saveStatus = .saving
        Task {
            do {
                try await claudeService.saveAgent(agent)
                saveStatus = .saved
                selectedAgent = claudeService.agents.first { $0.name == agent.name }
            } catch {
                saveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func deleteSelected() {
        guard let agent = selectedAgent else { return }
        Task {
            do {
                try await claudeService.deleteAgent(agent)
                selectedAgent = nil
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func createAgent(_ agent: Agent) {
        Task {
            do {
                try await claudeService.saveAgent(agent)
                selectedAgent = claudeService.agents.first { $0.name == agent.name }
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(agent.name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                Spacer()
                ModelBadge(model: agent.model)
            }
            if !agent.description.isEmpty {
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model Badge

private struct ModelBadge: View {
    let model: String

    private var displayName: String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        return model
    }

    private var badgeColor: Color {
        if model.contains("opus") { return .green }
        if model.contains("sonnet") { return Color(red: 0.48, green: 0.64, blue: 0.97) }
        return .gray
    }

    var body: some View {
        Text(displayName)
            .font(.caption2.bold())
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.15))
            )
    }
}

// MARK: - Create Agent Sheet

private struct CreateAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var model = "claude-sonnet-4-6"
    @State private var selectedTools: Set<String> = []
    let onCreate: (Agent) -> Void

    private let availableModels = [
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001"
    ]

    private let availableTools = [
        "Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("New Agent")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("my-agent", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("What does this agent do?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Picker("", selection: $model) {
                    ForEach(availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tools")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                    ForEach(availableTools, id: \.self) { tool in
                        ToolToggle(tool: tool, isSelected: selectedTools.contains(tool)) {
                            if selectedTools.contains(tool) {
                                selectedTools.remove(tool)
                            } else {
                                selectedTools.insert(tool)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let toolsList = Array(selectedTools).sorted()
                    let toolsYaml = toolsList.isEmpty ? "[]" : "[\(toolsList.joined(separator: ", "))]"
                    let template = """
                    ---
                    name: \(name)
                    description: "\(description)"
                    model: \(model)
                    tools: \(toolsYaml)
                    ---

                    # \(name)

                    """
                    let agent = Agent(
                        name: name,
                        description: description,
                        model: model,
                        tools: toolsList,
                        content: template,
                        filePath: "",
                        isGlobal: true
                    )
                    onCreate(agent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}

private struct ToolToggle: View {
    let tool: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tool)
                .font(.caption)
                .foregroundStyle(isSelected
                    ? Color(red: 0.75, green: 0.80, blue: 0.97)
                    : Color(red: 0.34, green: 0.37, blue: 0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                            ? Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.2)
                            : Color(red: 0.13, green: 0.14, blue: 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected
                            ? Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.5)
                            : Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.3),
                            lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
