import SwiftUI

// MARK: - Env Var Info

struct EnvVarInfo: Sendable {
    let key: String
    let description: String
    let defaultValue: String
    let category: String
}

private let knownEnvVars: [EnvVarInfo] = [
    EnvVarInfo(key: "ANTHROPIC_API_KEY", description: "API key for Claude authentication", defaultValue: "", category: "API & Auth"),
    EnvVarInfo(key: "ANTHROPIC_BASE_URL", description: "Custom API endpoint URL", defaultValue: "", category: "API & Auth"),
    EnvVarInfo(key: "CLAUDE_CODE_API_KEY_HELPER", description: "Shell command for dynamic API key rotation", defaultValue: "", category: "API & Auth"),
    EnvVarInfo(key: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", description: "Enable multi-agent team coordination", defaultValue: "false", category: "Agent & Teams"),
    EnvVarInfo(key: "CLAUDE_CODE_MAX_OUTPUT_TOKENS", description: "Max tokens per response", defaultValue: "", category: "Model Behavior"),
    EnvVarInfo(key: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", description: "Disable telemetry and update checks", defaultValue: "0", category: "Network"),
    EnvVarInfo(key: "HTTP_PROXY", description: "HTTP proxy server URL", defaultValue: "", category: "Network"),
    EnvVarInfo(key: "HTTPS_PROXY", description: "HTTPS proxy server URL", defaultValue: "", category: "Network"),
    EnvVarInfo(key: "CLAUDE_CODE_SKIP_PACKAGE_LOCK", description: "Skip package-lock.json updates", defaultValue: "false", category: "Model Behavior"),
    EnvVarInfo(key: "MAX_THINKING_TOKENS", description: "Token budget for extended thinking", defaultValue: "10000", category: "Model Behavior"),
    EnvVarInfo(key: "BASH_DEFAULT_TIMEOUT_MS", description: "Default timeout for Bash tool (ms)", defaultValue: "120000", category: "Tools"),
    EnvVarInfo(key: "BASH_MAX_TIMEOUT_MS", description: "Maximum allowed Bash timeout (ms)", defaultValue: "600000", category: "Tools"),
]

// MARK: - Settings Level

private enum SettingsLevel: String, CaseIterable {
    case global = "Global"
    case project = "Project"
    case local = "Local"
}

struct SettingsView: View {
    @Environment(ClaudeService.self) private var claudeService
    @Environment(RepoService.self) private var repoService
    @State private var activeTab: SettingsTab = .structured
    @State private var activeLevel: SettingsLevel = .global
    @State private var selectedRepoPath: String?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    // Structured form state
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var allowPatterns: [String] = []
    @State private var denyPatterns: [String] = []
    @State private var saveStatus: SaveStatus = .idle
    @State private var showAddAllowSheet = false
    @State private var showAddDenySheet = false

    // Env vars state
    @State private var envValues: [String: String] = [:]
    @State private var expandedCategories: Set<String> = []

    // Integrations
    @State private var githubPAT: String = ""

    // Raw JSON state
    @State private var rawJSON = "{}"
    @State private var rawSaveStatus: SaveStatus = .idle

    private enum SettingsTab: String, CaseIterable {
        case structured = "Structured"
        case json = "JSON Raw"
    }

    private enum SaveStatus {
        case idle, saving, saved
    }

    private let modelOptions = [
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Level picker header
            HStack(spacing: 16) {
                Picker("Level", selection: $activeLevel) {
                    ForEach(SettingsLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                if activeLevel != .global {
                    Picker("Repository", selection: $selectedRepoPath) {
                        Text("Select repo...").tag(nil as String?)
                        ForEach(repoService.repos) { repo in
                            Text(repo.name).tag(repo.path as String?)
                        }
                    }
                    .frame(maxWidth: 220)
                }

                Spacer()

                Picker("View", selection: $activeTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0.13, green: 0.14, blue: 0.18))

            // Content
            switch activeTab {
            case .structured:
                structuredView
            case .json:
                jsonRawView
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .task { await loadFromService() }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .structured {
                loadStructuredForCurrentLevel()
            } else {
                rawJSON = settingsContent(for: activeLevel, repoPath: selectedRepoPath)
                rawSaveStatus = .idle
            }
        }
        .onChange(of: activeLevel) { _, _ in
            reloadForCurrentLevel()
        }
        .onChange(of: selectedRepoPath) { _, _ in
            reloadForCurrentLevel()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showAddAllowSheet) {
            AddPatternSheet(title: "Add Allow Pattern") { pattern in
                allowPatterns.append(pattern)
            }
        }
        .sheet(isPresented: $showAddDenySheet) {
            AddPatternSheet(title: "Add Deny Pattern") { pattern in
                denyPatterns.append(pattern)
            }
        }
    }

    // MARK: - Level Helpers

    private func settingsContent(for level: SettingsLevel, repoPath: String?) -> String {
        if level == .global {
            return claudeService.rawSettingsContent()
        }
        guard let base = repoPath.map({ URL(fileURLWithPath: $0) }) else { return "{}" }
        let file: URL
        switch level {
        case .project: file = base.appendingPathComponent(".claude/settings.json")
        case .local:   file = base.appendingPathComponent(".claude/settings.local.json")
        case .global:  return claudeService.rawSettingsContent()
        }
        return (try? String(contentsOf: file, encoding: .utf8)) ?? "{}"
    }

    private func saveSettingsContent(_ content: String, for level: SettingsLevel, repoPath: String?) throws {
        if level == .global {
            // Handled via async claudeService.saveRawSettings
            return
        }
        guard let base = repoPath.map({ URL(fileURLWithPath: $0) }) else { return }
        let file: URL
        switch level {
        case .project: file = base.appendingPathComponent(".claude/settings.json")
        case .local:   file = base.appendingPathComponent(".claude/settings.local.json")
        case .global:  return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func reloadForCurrentLevel() {
        if activeTab == .structured {
            loadStructuredForCurrentLevel()
        } else {
            rawJSON = settingsContent(for: activeLevel, repoPath: selectedRepoPath)
            rawSaveStatus = .idle
        }
    }

    private func loadStructuredForCurrentLevel() {
        if activeLevel == .global {
            loadStructuredFromService()
        } else {
            let content = settingsContent(for: activeLevel, repoPath: selectedRepoPath)
            if let data = content.data(using: .utf8),
               let settings = try? JSONDecoder().decode(ClaudeSettings.self, from: data) {
                selectedModel = settings.model ?? "claude-sonnet-4-6"
                allowPatterns = settings.permissions?.allow ?? []
                denyPatterns = settings.permissions?.deny ?? []
                envValues = settings.env ?? [:]
            } else {
                selectedModel = "claude-sonnet-4-6"
                allowPatterns = []
                denyPatterns = []
                envValues = [:]
            }
        }
        saveStatus = .idle
    }

    private var currentLevelLabel: String {
        switch activeLevel {
        case .global: return "~/.claude/settings.json"
        case .project:
            guard let path = selectedRepoPath else { return "Select a repo" }
            return "\(URL(fileURLWithPath: path).lastPathComponent)/.claude/settings.json"
        case .local:
            guard let path = selectedRepoPath else { return "Select a repo" }
            return "\(URL(fileURLWithPath: path).lastPathComponent)/.claude/settings.local.json"
        }
    }

    // MARK: - Structured View

    private var structuredView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Model section
                    sectionHeader("Model")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default model for Claude Code")
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                        Picker("Model", selection: $selectedModel) {
                            ForEach(modelOptions, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }

                    Divider()
                        .background(Color(red: 0.18, green: 0.19, blue: 0.25))

                    // Integrations
                    sectionHeader("Integrations")
                    integrationsSection

                    Divider()
                        .background(Color(red: 0.18, green: 0.19, blue: 0.25))

                    // Allow permissions
                    sectionHeader("Permissions — Allow")
                    permissionsList(
                        patterns: $allowPatterns,
                        emptyText: "No allow patterns configured",
                        onAdd: { showAddAllowSheet = true }
                    )

                    Divider()
                        .background(Color(red: 0.18, green: 0.19, blue: 0.25))

                    // Deny permissions
                    sectionHeader("Permissions — Deny")
                    permissionsList(
                        patterns: $denyPatterns,
                        emptyText: "No deny patterns configured",
                        onAdd: { showAddDenySheet = true }
                    )

                    Divider()
                        .background(Color(red: 0.18, green: 0.19, blue: 0.25))

                    // Environment Variables section
                    sectionHeader("Environment Variables")
                    envVarsSection
                }
                .padding(24)
            }

            // Bottom bar
            structuredBottomBar
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                    Text("GitHub Personal Access Token")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                }
                Text("Used by the GitHub MCP server for repo operations (create, push, etc.). Generate at github.com/settings/tokens")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))

                SecureField("ghp_...", text: $githubPAT)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                if !githubPAT.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                        Text("PAT configured — GitHub MCP will be active")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.13, green: 0.14, blue: 0.18))
            )
        }
    }

    // MARK: - Env Vars Section

    private var envVarCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for v in knownEnvVars {
            if seen.insert(v.category).inserted {
                result.append(v.category)
            }
        }
        return result
    }

    private var envVarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(envVarCategories, id: \.self) { category in
                envVarCategorySection(category)
            }
        }
    }

    private func envVarCategorySection(_ category: String) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let vars = knownEnvVars.filter { $0.category == category }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                        .frame(width: 12)
                    Text(category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    Spacer()
                    let setCount = vars.filter { !(envValues[$0.key] ?? "").isEmpty }.count
                    if setCount > 0 {
                        Text("\(setCount) set")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.15)))
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(vars, id: \.key) { envVar in
                        envVarRow(envVar)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.18))
        )
    }

    private func envVarRow(_ info: EnvVarInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(info.key)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

                if !info.defaultValue.isEmpty {
                    Text("default: \(info.defaultValue)")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(red: 0.18, green: 0.19, blue: 0.25))
                        )
                }
                Spacer()
            }

            Text(info.description)
                .font(.caption2)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))

            TextField("Not set", text: Binding(
                get: { envValues[info.key] ?? "" },
                set: { envValues[info.key] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
    }

    private func permissionsList(patterns: Binding<[String]>, emptyText: String, onAdd: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if patterns.wrappedValue.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(patterns.wrappedValue.enumerated()), id: \.offset) { index, pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                        Spacer()
                        Button {
                            patterns.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 0.13, green: 0.14, blue: 0.18))
                    )
                }
            }
            Button {
                onAdd()
            } label: {
                Label("Add Pattern", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
        }
    }

    private var structuredBottomBar: some View {
        HStack {
            Text(currentLevelLabel)
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
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
            Button("Save") { saveStructured() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - JSON Raw View

    private var jsonRawView: some View {
        VStack(spacing: 0) {
            WebEditorView(
                content: $rawJSON,
                language: "json",
                isReadOnly: false,
                onSave: { saveRawJSON() }
            )

            // Bottom bar
            HStack {
                Text(currentLevelLabel)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Spacer()
                switch rawSaveStatus {
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
                Button("Save") { saveRawJSON() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.13, green: 0.14, blue: 0.18))
        }
    }

    // MARK: - Data Loading

    private func loadFromService() async {
        await claudeService.loadSettings()
        loadStructuredFromService()
        rawJSON = claudeService.rawSettingsContent()
        githubPAT = claudeService.loadGitHubPAT()
    }

    private func loadStructuredFromService() {
        let settings = claudeService.globalSettings
        selectedModel = settings.model ?? "claude-sonnet-4-6"
        allowPatterns = settings.permissions?.allow ?? []
        denyPatterns = settings.permissions?.deny ?? []
        envValues = settings.env ?? [:]
        saveStatus = .idle
    }

    // MARK: - Save Actions

    private func saveStructured() {
        saveStatus = .saving
        let env = envValues.filter { !$0.value.isEmpty }
        let settings = ClaudeSettings(
            model: selectedModel,
            permissions: ClaudeSettings.Permissions(
                allow: allowPatterns.isEmpty ? nil : allowPatterns,
                deny: denyPatterns.isEmpty ? nil : denyPatterns
            ),
            env: env.isEmpty ? nil : env
        )

        Task {
            do {
                // Save GitHub PAT to MCP config
                try await claudeService.saveGitHubPAT(githubPAT)

                if activeLevel == .global {
                    try await claudeService.saveSettings(settings)
                    rawJSON = claudeService.rawSettingsContent()
                } else {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(settings)
                    let json = String(data: data, encoding: .utf8) ?? "{}"
                    try saveSettingsContent(json, for: activeLevel, repoPath: selectedRepoPath)
                }
                saveStatus = .saved
            } catch {
                saveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func saveRawJSON() {
        rawSaveStatus = .saving
        Task {
            do {
                if activeLevel == .global {
                    try await claudeService.saveRawSettings(rawJSON)
                    loadStructuredFromService()
                } else {
                    try saveSettingsContent(rawJSON, for: activeLevel, repoPath: selectedRepoPath)
                }
                rawSaveStatus = .saved
            } catch {
                rawSaveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Add Pattern Sheet

private struct AddPatternSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onAdd: (String) -> Void
    @State private var pattern = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("e.g. Bash(npm run *)", text: $pattern)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let trimmed = pattern.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onAdd(trimmed)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}
