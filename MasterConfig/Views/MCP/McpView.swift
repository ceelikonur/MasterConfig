import SwiftUI

// MARK: - Tab Level

private enum McpTabLevel: String, CaseIterable {
    case global  = "Global"
    case perRepo = "Per-Repo"
    case library = "Library"
}

// MARK: - Library Item Model

struct McpLibraryItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let category: String
    let icon: String
    let command: String
    let args: [String]
    let envKeys: [String]          // Required env var names
    let envDescriptions: [String]  // Human-readable descriptions for each key
    let docsURL: String

    static let all: [McpLibraryItem] = [
        McpLibraryItem(
            name: "github",
            description: "Access GitHub repos, issues, PRs, code search and more.",
            category: "Dev Tools",
            icon: "chevron.left.forwardslash.chevron.right",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            envKeys: ["GITHUB_PERSONAL_ACCESS_TOKEN"],
            envDescriptions: ["GitHub PAT with repo scope — github.com/settings/tokens"],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/github"
        ),
        McpLibraryItem(
            name: "supabase",
            description: "Read and write Supabase database tables, run SQL, manage auth.",
            category: "Database",
            icon: "cylinder.split.1x2",
            command: "npx",
            args: ["-y", "@supabase/mcp-server-supabase@latest"],
            envKeys: ["SUPABASE_ACCESS_TOKEN"],
            envDescriptions: ["Supabase PAT — app.supabase.com/account/tokens"],
            docsURL: "https://github.com/supabase-community/supabase-mcp"
        ),
        McpLibraryItem(
            name: "filesystem",
            description: "Read, write, and search files in specified directories.",
            category: "Files",
            icon: "folder",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "~/Desktop"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem"
        ),
        McpLibraryItem(
            name: "postgres",
            description: "Query and manage PostgreSQL databases.",
            category: "Database",
            icon: "tablecells",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/mydb"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/postgres"
        ),
        McpLibraryItem(
            name: "brave-search",
            description: "Web and local search via Brave Search API.",
            category: "Search",
            icon: "magnifyingglass.circle",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-brave-search"],
            envKeys: ["BRAVE_API_KEY"],
            envDescriptions: ["Brave Search API key — brave.com/search/api"],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/brave-search"
        ),
        McpLibraryItem(
            name: "fetch",
            description: "Fetch web pages and convert them to markdown.",
            category: "Web",
            icon: "globe",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-fetch"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch"
        ),
        McpLibraryItem(
            name: "memory",
            description: "Persistent knowledge graph memory across conversations.",
            category: "AI",
            icon: "brain",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/memory"
        ),
        McpLibraryItem(
            name: "puppeteer",
            description: "Browser automation — screenshots, forms, scraping.",
            category: "Web",
            icon: "desktopcomputer",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-puppeteer"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/puppeteer"
        ),
        McpLibraryItem(
            name: "slack",
            description: "Send messages, read channels, search Slack workspace.",
            category: "Communication",
            icon: "message",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-slack"],
            envKeys: ["SLACK_BOT_TOKEN", "SLACK_TEAM_ID"],
            envDescriptions: ["Bot token (xoxb-...) — api.slack.com/apps", "Workspace team ID"],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/slack"
        ),
        McpLibraryItem(
            name: "gitlab",
            description: "GitLab repos, issues, MRs, CI/CD pipelines.",
            category: "Dev Tools",
            icon: "chevron.left.forwardslash.chevron.right",
            command: "npx",
            args: ["-y", "@gitlabmcp/server"],
            envKeys: ["GITLAB_TOKEN", "GITLAB_URL"],
            envDescriptions: ["GitLab PAT with api scope", "GitLab instance URL (e.g. https://gitlab.com)"],
            docsURL: "https://gitlab.com/gitlab-org/gitlab-mcp"
        ),
        McpLibraryItem(
            name: "sqlite",
            description: "Read and query SQLite databases.",
            category: "Database",
            icon: "tablecells",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "~/data.db"],
            envKeys: [],
            envDescriptions: [],
            docsURL: "https://github.com/modelcontextprotocol/servers/tree/main/src/sqlite"
        ),
        McpLibraryItem(
            name: "linear",
            description: "Manage Linear issues, projects, and teams.",
            category: "Dev Tools",
            icon: "checklist",
            command: "npx",
            args: ["-y", "@linear/mcp-server"],
            envKeys: ["LINEAR_API_KEY"],
            envDescriptions: ["Linear API key — linear.app/settings/api"],
            docsURL: "https://github.com/linear/linear-mcp-server"
        ),
    ]
}

// MARK: - Discovered Script

struct DiscoveredScript: Identifiable, Hashable {
    let id = UUID()
    let fileName: String       // "sap-mcp.ts"
    let absolutePath: String   // full path on disk
    let repoPath: String       // repo root this belongs to
    var suggestedName: String  // "sap" stripped from filename
}

// MARK: - McpView

struct McpView: View {
    @Environment(ClaudeService.self) private var claudeService
    @Environment(RepoService.self) private var repoService
    @State private var activeLevel: McpTabLevel = .global
    @State private var selectedServer: McpServer?
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var showCopySheet = false
    @State private var showLibraryAddSheet = false
    @State private var selectedLibraryItem: McpLibraryItem?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    @State private var selectedRepoPath: String?
    @State private var repoServers: [McpServer] = []
    @State private var discoveredScripts: [DiscoveredScript] = []
    @State private var scriptToRegister: DiscoveredScript?

    @State private var editName = ""
    @State private var editCommand = ""
    @State private var editArgs = ""
    @State private var editEnvKeys: [String] = []
    @State private var editEnvVals: [String] = []
    @State private var editScope: McpServer.McpScope = .global
    @State private var saveStatus: SaveStatus = .idle

    private enum SaveStatus { case idle, saving, saved }

    private var currentServers: [McpServer] {
        activeLevel == .global ? claudeService.mcpServers : repoServers
    }

    private var filteredServers: [McpServer] {
        let servers = currentServers
        if searchText.isEmpty { return servers }
        let q = searchText.lowercased()
        return servers.filter { $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if activeLevel == .library {
                LibraryTabView(
                    repos: repoService.repos,
                    onAddToGlobal: { item, envVals in addLibraryItemToGlobal(item, envVals: envVals) },
                    onAddToRepo: { item, repoPath, envVals in addLibraryItemToRepo(item, repoPath: repoPath, envVals: envVals) }
                )
            } else {
                HSplitView {
                    serverList.frame(minWidth: 220, idealWidth: 280, maxWidth: 340)
                    detailPanel.frame(minWidth: 400)
                }
            }
        }
        .task { await claudeService.loadMCPServers() }
        .onChange(of: activeLevel) { _, _ in
            selectedServer = nil
            searchText = ""
            discoveredScripts = []
            if activeLevel == .perRepo { loadRepoServers() }
        }
        .onChange(of: selectedRepoPath) { _, _ in
            selectedServer = nil
            loadRepoServers()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Unknown error") }
        .alert("Delete Server", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Delete \"\(selectedServer?.name ?? "")\"? This cannot be undone.") }
        .sheet(isPresented: $showCreateSheet) {
            CreateMcpServerSheet { server in
                activeLevel == .global ? createServer(server) : createRepoServer(server)
            }
        }
        .sheet(isPresented: $showCopySheet) {
            if let server = selectedServer {
                CopyToRepoSheet(
                    server: server,
                    sourceRepoPath: activeLevel == .perRepo ? selectedRepoPath : nil,
                    repos: repoService.repos,
                    currentRepoPath: activeLevel == .perRepo ? selectedRepoPath : nil,
                    onCopy: { repoPaths in copyServer(server, toRepoPaths: repoPaths, sourceRepoPath: activeLevel == .perRepo ? selectedRepoPath : nil) }
                )
            }
        }
        .sheet(item: $scriptToRegister) { script in
            RegisterScriptSheet(script: script) { server in
                registerScript(server: server, repoPath: script.repoPath)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            Picker("Level", selection: $activeLevel) {
                ForEach(McpTabLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            if activeLevel == .perRepo {
                Picker("Repository", selection: $selectedRepoPath) {
                    Text("Select repo...").tag(nil as String?)
                    ForEach(repoService.repos) { repo in
                        Text(repo.name).tag(repo.path as String?)
                    }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Server List

    private var serverList: some View {
        VStack(spacing: 0) {
            searchField
            if filteredServers.isEmpty && discoveredScripts.isEmpty {
                emptyListPlaceholder
            } else {
                List(selection: $selectedServer) {
                    if !filteredServers.isEmpty {
                        Section {
                            ForEach(filteredServers) { server in
                                ServerRow(server: server).tag(server)
                            }
                        }
                    }
                    if activeLevel == .perRepo && !discoveredScripts.isEmpty {
                        Section {
                            ForEach(discoveredScripts) { script in
                                DiscoveredScriptRow(script: script) {
                                    scriptToRegister = script
                                }
                            }
                        } header: {
                            Text("Unregistered Scripts")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.orange.opacity(0.8))
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if activeLevel == .perRepo && !repoServers.isEmpty {
                    Button { promoteAllToGlobal() } label: {
                        Label("Promote All to Global", systemImage: "arrow.up.circle")
                    }
                    .help("Copy all per-repo servers to global ~/.claude.json")
                }
                if selectedServer != nil {
                    Button { showCopySheet = true } label: {
                        Label("Copy to Repo...", systemImage: "doc.on.doc")
                    }
                    .help("Copy this server to one or more repos")
                }
                Button { showCreateSheet = true } label: {
                    Label("Add Server", systemImage: "plus")
                }
                Button { if selectedServer != nil { showDeleteAlert = true } } label: {
                    Label("Delete Server", systemImage: "minus")
                }
                .disabled(selectedServer == nil)
            }
        }
        .onChange(of: selectedServer) { _, newValue in
            loadFormFromServer(newValue)
            saveStatus = .idle
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            TextField("Filter servers...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
        }
        .padding(8)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    private var emptyListPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            if activeLevel == .perRepo && selectedRepoPath == nil {
                Text("Select a repository")
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            } else {
                Text("No MCP servers")
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                if searchText.isEmpty {
                    Text("Click + to add, or browse the Library tab")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if selectedServer != nil { editForm }
            else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("Select a server to edit")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("Or browse the Library tab to add popular MCPs")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.1, green: 0.11, blue: 0.15))
            }
        }
    }

    private var editForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    formField(label: "Name") {
                        TextField("server-name", text: $editName).textFieldStyle(.roundedBorder)
                    }
                    formField(label: "Command") {
                        TextField("/usr/local/bin/npx", text: $editCommand).textFieldStyle(.roundedBorder)
                    }
                    formField(label: "Arguments (comma-separated)") {
                        TextField("-y, @modelcontextprotocol/server-name", text: $editArgs).textFieldStyle(.roundedBorder)
                    }
                    envVarsEditor
                    if activeLevel == .global {
                        formField(label: "Scope") {
                            Picker("Scope", selection: $editScope) {
                                ForEach(McpServer.McpScope.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            .pickerStyle(.segmented).frame(maxWidth: 200)
                        }
                    }
                }
                .padding(24)
            }
            bottomBar
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
    }

    private var envVarsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Environment Variables")
                    .font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Spacer()
                Button { editEnvKeys.append(""); editEnvVals.append("") } label: {
                    Label("Add", systemImage: "plus.circle").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
            }
            if editEnvKeys.isEmpty {
                Text("No environment variables").font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55)).padding(.vertical, 4)
            } else {
                ForEach(editEnvKeys.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("KEY", text: Binding(
                            get: { i < editEnvKeys.count ? editEnvKeys[i] : "" },
                            set: { if i < editEnvKeys.count { editEnvKeys[i] = $0 } }
                        )).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        Text("=").foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                        TextField("value", text: Binding(
                            get: { i < editEnvVals.count ? editEnvVals[i] : "" },
                            set: { if i < editEnvVals.count { editEnvVals[i] = $0 } }
                        )).textFieldStyle(.roundedBorder)
                        Button {
                            if i < editEnvKeys.count { editEnvKeys.remove(at: i); editEnvVals.remove(at: i) }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.7)) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            if let server = selectedServer {
                mcpScopeBadge(server.scope)
                Text(server.name).font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55)).lineLimit(1)
            }
            Spacer()
            switch saveStatus {
            case .idle: EmptyView()
            case .saving:
                ProgressView().controlSize(.small)
                Text("Saving...").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            case .saved:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Saved").font(.caption).foregroundStyle(.green)
            }
            Button("Save") { saveCurrentServer() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            content()
        }
    }

    // MARK: - Per-Repo Helpers

    private func loadRepoServers() {
        guard let path = selectedRepoPath else {
            repoServers = []
            discoveredScripts = []
            return
        }
        repoServers = loadRepoMcp(path: path)
        discoveredScripts = scanForUnregisteredScripts(repoPath: path, registered: repoServers)
    }

    private func scanForUnregisteredScripts(repoPath: String, registered: [McpServer]) -> [DiscoveredScript] {
        let fm = FileManager.default
        // Paths to scan for MCP-like scripts
        let scanDirs = ["scripts", ".claude/mcps", "mcp", "mcps"]
        let extensions = ["ts", "js", "mjs", "py"]
        let mcpKeywords = ["mcp", "server"]

        // Collect all args from registered servers (to detect already-registered scripts)
        let registeredArgs = Set(registered.flatMap { $0.args })

        var found: [DiscoveredScript] = []
        for dir in scanDirs {
            let dirURL = URL(fileURLWithPath: repoPath).appendingPathComponent(dir)
            guard fm.fileExists(atPath: dirURL.path),
                  let files = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            else { continue }

            for file in files {
                guard extensions.contains(file.pathExtension) else { continue }
                let name = file.deletingPathExtension().lastPathComponent.lowercased()
                // Must contain "mcp" or "server" in the filename
                guard mcpKeywords.contains(where: { name.contains($0) }) else { continue }
                // Skip if already referenced in any registered server's args
                let relPath = "\(dir)/\(file.lastPathComponent)"
                if registeredArgs.contains(where: { $0.contains(file.lastPathComponent) || $0.contains(relPath) }) { continue }

                // Derive clean suggested name: "sap-mcp.ts" → "sap", "my-server-mcp.ts" → "my-server"
                var suggested = file.deletingPathExtension().lastPathComponent
                for suffix in ["-mcp", "_mcp", "-server", "_server"] {
                    if suggested.hasSuffix(suffix) {
                        suggested = String(suggested.dropLast(suffix.count))
                        break
                    }
                }
                found.append(DiscoveredScript(
                    fileName: file.lastPathComponent,
                    absolutePath: file.path,
                    repoPath: repoPath,
                    suggestedName: suggested
                ))
            }
        }
        return found.sorted { $0.fileName < $1.fileName }
    }

    private func registerScript(server: McpServer, repoPath: String) {
        var updated = repoServers
        updated.append(server)
        updated.sort { $0.name < $1.name }
        do {
            try saveRepoMcp(updated, path: repoPath)
            repoServers = updated
            discoveredScripts = scanForUnregisteredScripts(repoPath: repoPath, registered: updated)
            selectedServer = updated.first { $0.name == server.name }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func loadRepoMcp(path: String) -> [McpServer] {
        let url = URL(fileURLWithPath: path).appendingPathComponent(".mcp.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return [] }
        return servers.compactMap { name, value in
            guard let config = value as? [String: Any] else { return nil }
            return McpServer(name: name, command: config["command"] as? String ?? "",
                             args: config["args"] as? [String] ?? [],
                             env: config["env"] as? [String: String] ?? [:], scope: .local)
        }.sorted { $0.name < $1.name }
    }

    private func saveRepoMcp(_ servers: [McpServer], path: String) throws {
        let url = URL(fileURLWithPath: path).appendingPathComponent(".mcp.json")
        var dict: [String: Any] = [:]
        for s in servers {
            dict[s.name] = ["command": s.command, "args": s.args, "env": s.env]
        }
        let json = try JSONSerialization.data(withJSONObject: ["mcpServers": dict], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: url)
    }

    private func promoteAllToGlobal() {
        guard !repoServers.isEmpty else { return }
        Task {
            do {
                for server in repoServers {
                    let gs = McpServer(name: server.name, command: server.command, args: server.args, env: server.env, scope: .global)
                    try await claudeService.saveMCPServer(gs)
                }
                saveStatus = .saved
            } catch {
                errorMessage = error.localizedDescription; showErrorAlert = true
            }
        }
    }

    // MARK: - Copy to Repo

    private func copyServer(_ server: McpServer, toRepoPaths paths: [String], sourceRepoPath: String? = nil) {
        for path in paths {
            // Convert relative script paths to absolute using source repo path
            let resolvedArgs: [String]
            if let srcRepo = sourceRepoPath {
                resolvedArgs = server.args.map { arg -> String in
                    // Detect relative paths: starts with scripts/, ./, or contains /mcp
                    let looksRelative = arg.hasPrefix("scripts/") || arg.hasPrefix("./") ||
                        arg.hasPrefix(".claude/") || arg.hasPrefix("mcp/")
                    if looksRelative {
                        return URL(fileURLWithPath: srcRepo).appendingPathComponent(arg).path
                    }
                    return arg
                }
            } else {
                resolvedArgs = server.args
            }

            var servers = loadRepoMcp(path: path)
            let local = McpServer(name: server.name, command: server.command,
                                  args: resolvedArgs, env: server.env, scope: .local)
            if let idx = servers.firstIndex(where: { $0.name == local.name }) { servers[idx] = local }
            else { servers.append(local) }
            servers.sort { $0.name < $1.name }
            try? saveRepoMcp(servers, path: path)
        }
        if activeLevel == .perRepo { loadRepoServers() }
    }

    // MARK: - Library Add

    private func addLibraryItemToGlobal(_ item: McpLibraryItem, envVals: [String: String]) {
        let server = McpServer(name: item.name, command: item.command, args: item.args, env: envVals, scope: .global)
        Task {
            do {
                try await claudeService.saveMCPServer(server)
                activeLevel = .global
                selectedServer = claudeService.mcpServers.first { $0.name == server.name }
            } catch {
                errorMessage = error.localizedDescription; showErrorAlert = true
            }
        }
    }

    private func addLibraryItemToRepo(_ item: McpLibraryItem, repoPath: String, envVals: [String: String]) {
        let server = McpServer(name: item.name, command: item.command, args: item.args, env: envVals, scope: .local)
        var servers = loadRepoMcp(path: repoPath)
        if let idx = servers.firstIndex(where: { $0.name == server.name }) { servers[idx] = server }
        else { servers.append(server) }
        servers.sort { $0.name < $1.name }
        do {
            try saveRepoMcp(servers, path: repoPath)
            if selectedRepoPath == repoPath {
                repoServers = servers
                activeLevel = .perRepo
                selectedServer = servers.first { $0.name == server.name }
            }
        } catch {
            errorMessage = error.localizedDescription; showErrorAlert = true
        }
    }

    // MARK: - CRUD Actions

    private func loadFormFromServer(_ server: McpServer?) {
        guard let server else {
            editName = ""; editCommand = ""; editArgs = ""
            editEnvKeys = []; editEnvVals = []; editScope = .global; return
        }
        editName = server.name; editCommand = server.command
        editArgs = server.args.joined(separator: ", ")
        editEnvKeys = Array(server.env.keys.sorted())
        editEnvVals = editEnvKeys.map { server.env[$0] ?? "" }
        editScope = server.scope
    }

    private func buildServerFromForm() -> McpServer {
        let args = editArgs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var env: [String: String] = [:]
        for i in 0..<min(editEnvKeys.count, editEnvVals.count) {
            let key = editEnvKeys[i].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { env[key] = editEnvVals[i] }
        }
        return McpServer(name: editName.trimmingCharacters(in: .whitespaces),
                         command: editCommand.trimmingCharacters(in: .whitespaces),
                         args: args, env: env,
                         scope: activeLevel == .global ? editScope : .local)
    }

    private func saveCurrentServer() {
        let server = buildServerFromForm()
        guard !server.name.isEmpty, !server.command.isEmpty else {
            errorMessage = "Name and command are required."; showErrorAlert = true; return
        }
        saveStatus = .saving
        if activeLevel == .global {
            Task {
                do {
                    if let old = selectedServer, old.name != server.name { try await claudeService.deleteMCPServer(old) }
                    try await claudeService.saveMCPServer(server)
                    saveStatus = .saved
                    selectedServer = claudeService.mcpServers.first { $0.name == server.name }
                } catch { saveStatus = .idle; errorMessage = error.localizedDescription; showErrorAlert = true }
            }
        } else {
            guard let path = selectedRepoPath else { return }
            do {
                var updated = repoServers
                if let old = selectedServer, old.name != server.name { updated.removeAll { $0.name == old.name } }
                if let idx = updated.firstIndex(where: { $0.name == server.name }) { updated[idx] = server }
                else { updated.append(server) }
                updated.sort { $0.name < $1.name }
                try saveRepoMcp(updated, path: path)
                repoServers = updated; saveStatus = .saved
                selectedServer = updated.first { $0.name == server.name }
            } catch { saveStatus = .idle; errorMessage = error.localizedDescription; showErrorAlert = true }
        }
    }

    private func deleteSelected() {
        guard let server = selectedServer else { return }
        if activeLevel == .global {
            Task {
                do { try await claudeService.deleteMCPServer(server); selectedServer = nil }
                catch { errorMessage = error.localizedDescription; showErrorAlert = true }
            }
        } else {
            guard let path = selectedRepoPath else { return }
            var updated = repoServers
            updated.removeAll { $0.name == server.name }
            do { try saveRepoMcp(updated, path: path); repoServers = updated; selectedServer = nil }
            catch { errorMessage = error.localizedDescription; showErrorAlert = true }
        }
    }

    private func createServer(_ server: McpServer) {
        Task {
            do {
                try await claudeService.saveMCPServer(server)
                selectedServer = claudeService.mcpServers.first { $0.name == server.name }
            } catch { errorMessage = error.localizedDescription; showErrorAlert = true }
        }
    }

    private func createRepoServer(_ server: McpServer) {
        guard let path = selectedRepoPath else { return }
        var updated = repoServers
        let local = McpServer(name: server.name, command: server.command, args: server.args, env: server.env, scope: .local)
        updated.append(local); updated.sort { $0.name < $1.name }
        do {
            try saveRepoMcp(updated, path: path)
            repoServers = updated
            selectedServer = updated.first { $0.name == server.name }
        } catch { errorMessage = error.localizedDescription; showErrorAlert = true }
    }
}

// MARK: - Library Tab View

private struct LibraryTabView: View {
    let repos: [Repo]
    let onAddToGlobal: (McpLibraryItem, [String: String]) -> Void
    let onAddToRepo: (McpLibraryItem, String, [String: String]) -> Void

    @State private var selectedItem: McpLibraryItem?
    @State private var searchText = ""

    private var categories: [String] {
        Array(Set(McpLibraryItem.all.map(\.category))).sorted()
    }

    private var filtered: [McpLibraryItem] {
        if searchText.isEmpty { return McpLibraryItem.all }
        let q = searchText.lowercased()
        return McpLibraryItem.all.filter { $0.name.contains(q) || $0.description.lowercased().contains(q) || $0.category.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("Search MCPs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
            }
            .padding(10)
            .background(Color(red: 0.13, green: 0.14, blue: 0.18))

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(categories, id: \.self) { category in
                        let items = filtered.filter { $0.category == category }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                                    .padding(.horizontal, 4)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                                    ForEach(items) { item in
                                        LibraryCard(item: item) {
                                            selectedItem = item
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .sheet(item: $selectedItem) { item in
            AddLibraryItemSheet(
                item: item,
                repos: repos,
                onAddToGlobal: { envVals in onAddToGlobal(item, envVals) },
                onAddToRepo: { repoPath, envVals in onAddToRepo(item, repoPath, envVals) }
            )
        }
    }
}

// MARK: - Library Card

private struct LibraryCard: View {
    let item: McpLibraryItem
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    if !item.envKeys.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "key").font(.caption2)
                                .foregroundStyle(Color.orange.opacity(0.8))
                            Text(item.envKeys.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(Color.orange.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                }
                .buttonStyle(.plain)
                .help("Add to Global or Per-Repo")
            }
            Text(item.description)
                .font(.caption)
                .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))
                .lineLimit(2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: isHovered ? 0.16 : 0.13, green: isHovered ? 0.17 : 0.14, blue: isHovered ? 0.22 : 0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    Color(red: 0.34, green: 0.37, blue: 0.55).opacity(isHovered ? 0.5 : 0.2), lineWidth: 1))
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Add Library Item Sheet

private struct AddLibraryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: McpLibraryItem
    let repos: [Repo]
    let onAddToGlobal: ([String: String]) -> Void
    let onAddToRepo: (String, [String: String]) -> Void

    @State private var envVals: [String] = []
    @State private var destination: Destination = .global
    @State private var selectedRepoPath: String = ""

    enum Destination { case global, repo }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.title3.bold())
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))
                }
            }

            Divider().opacity(0.3)

            // Command preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Command").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Text("\(item.command) \(item.args.joined(separator: " "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
            }

            // Env vars (if needed)
            if !item.envKeys.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Required Credentials")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    ForEach(item.envKeys.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.envKeys[i])
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                                if i < item.envDescriptions.count {
                                    Text("— \(item.envDescriptions[i])")
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))
                                }
                            }
                            SecureField("Enter value...", text: Binding(
                                get: { i < envVals.count ? envVals[i] : "" },
                                set: { v in
                                    while envVals.count <= i { envVals.append("") }
                                    envVals[i] = v
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            Divider().opacity(0.3)

            // Destination picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Add to").font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Picker("Destination", selection: $destination) {
                    Text("Global (~/.claude.json)").tag(Destination.global)
                    Text("Specific Repo (.mcp.json)").tag(Destination.repo)
                }
                .pickerStyle(.segmented)

                if destination == .repo {
                    Picker("Repository", selection: $selectedRepoPath) {
                        Text("Select repo...").tag("")
                        ForEach(repos) { repo in
                            Text(repo.name).tag(repo.path)
                        }
                    }
                    .disabled(repos.isEmpty)
                }
            }

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add MCP") {
                    let envDict = buildEnvDict()
                    if destination == .global {
                        onAddToGlobal(envDict)
                    } else {
                        onAddToRepo(selectedRepoPath, envDict)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(destination == .repo && selectedRepoPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
        .onAppear { envVals = Array(repeating: "", count: item.envKeys.count) }
    }

    private func buildEnvDict() -> [String: String] {
        var dict: [String: String] = [:]
        for i in item.envKeys.indices {
            let val = i < envVals.count ? envVals[i] : ""
            if !val.isEmpty { dict[item.envKeys[i]] = val }
        }
        return dict
    }
}

// MARK: - Discovered Script Row

private struct DiscoveredScriptRow: View {
    let script: DiscoveredScript
    let onRegister: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.caption)
                .foregroundStyle(Color.orange.opacity(0.8))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(script.fileName)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                Text("Not in .mcp.json")
                    .font(.caption)
                    .foregroundStyle(Color.orange.opacity(0.6))
            }
            Spacer()
            Button("Register") { onRegister() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.5)))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Register Script Sheet

private struct RegisterScriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let script: DiscoveredScript
    let onRegister: (McpServer) -> Void

    @State private var name: String
    @State private var command = "npx"
    @State private var envKeys: [String] = []
    @State private var envVals: [String] = []

    init(script: DiscoveredScript, onRegister: @escaping (McpServer) -> Void) {
        self.script = script
        self.onRegister = onRegister
        _name = State(initialValue: script.suggestedName)
    }

    // Detect runtime from file extension
    private var detectedRunner: String {
        switch URL(fileURLWithPath: script.fileName).pathExtension {
        case "ts": return "tsx"
        case "py": return "python3"
        case "mjs", "js": return "node"
        default: return "node"
        }
    }

    private var argsPreview: [String] {
        if script.fileName.hasSuffix(".ts") {
            return ["tsx", script.absolutePath]
        } else if script.fileName.hasSuffix(".py") {
            return ["python3", script.absolutePath]
        } else {
            return [script.absolutePath]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.orange.opacity(0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Register MCP Script")
                        .font(.title3.bold())
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    Text(script.fileName)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))
                }
            }

            // Command preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Command that will be added to .mcp.json")
                    .font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Text("npx \(argsPreview.joined(separator: " "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                Text("Uses absolute path — works from any repo")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.48, green: 0.84, blue: 0.87))
            }

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Server Name").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("e.g. sap", text: $name).textFieldStyle(.roundedBorder)
            }

            // Env vars
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Environment Variables").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Spacer()
                    Button { envKeys.append(""); envVals.append("") } label: {
                        Label("Add", systemImage: "plus.circle").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                }
                if envKeys.isEmpty {
                    Text("No env vars needed (or add SAP_URL, SAP_USER, etc.)")
                        .font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                } else {
                    ForEach(envKeys.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            TextField("KEY", text: Binding(
                                get: { i < envKeys.count ? envKeys[i] : "" },
                                set: { if i < envKeys.count { envKeys[i] = $0 } }
                            )).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                            Text("=").foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                            SecureField("value", text: Binding(
                                get: { i < envVals.count ? envVals[i] : "" },
                                set: { if i < envVals.count { envVals[i] = $0 } }
                            )).textFieldStyle(.roundedBorder)
                            Button {
                                if i < envKeys.count { envKeys.remove(at: i); envVals.remove(at: i) }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.7)) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Register to .mcp.json") {
                    var env: [String: String] = [:]
                    for i in 0..<min(envKeys.count, envVals.count) {
                        let k = envKeys[i].trimmingCharacters(in: .whitespaces)
                        if !k.isEmpty { env[k] = envVals[i] }
                    }
                    let server = McpServer(
                        name: name.trimmingCharacters(in: .whitespaces).isEmpty ? script.suggestedName : name,
                        command: "npx",
                        args: argsPreview,
                        env: env,
                        scope: .local
                    )
                    onRegister(server)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
            }
        }
        .padding(24).frame(width: 500)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}

// MARK: - Copy To Repo Sheet

private struct CopyToRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let server: McpServer
    let sourceRepoPath: String?
    let repos: [Repo]
    let currentRepoPath: String?
    let onCopy: ([String]) -> Void

    @State private var selectedPaths: Set<String> = []

    private var availableRepos: [Repo] {
        repos.filter { $0.path != currentRepoPath }
    }

    private var hasLocalScript: Bool {
        server.args.contains { arg in
            arg.hasPrefix("scripts/") || arg.hasPrefix("./") ||
            arg.hasPrefix(".claude/") || arg.hasPrefix("mcp/")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Copy \"\(server.name)\" to Repos")
                .font(.title3.bold())
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

            if hasLocalScript && sourceRepoPath != nil {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color(red: 0.48, green: 0.84, blue: 0.87))
                    Text("This MCP uses a local script. The path will be converted to absolute so target repos can run it directly from \(URL(fileURLWithPath: sourceRepoPath!).lastPathComponent).")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.48, green: 0.84, blue: 0.87).opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.48, green: 0.84, blue: 0.87).opacity(0.3))))
            }

            Text("Select repos to add this server to their .mcp.json:")
                .font(.caption)
                .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))

            if availableRepos.isEmpty {
                Text("No other repos found")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // Select all toggle
                    Button {
                        if selectedPaths.count == availableRepos.count {
                            selectedPaths = []
                        } else {
                            selectedPaths = Set(availableRepos.map(\.path))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedPaths.count == availableRepos.count ? "checkmark.square.fill" : "square")
                                .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                            Text("Select All")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)

                    Divider().opacity(0.3)

                    ForEach(availableRepos) { repo in
                        Button {
                            if selectedPaths.contains(repo.path) { selectedPaths.remove(repo.path) }
                            else { selectedPaths.insert(repo.path) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedPaths.contains(repo.path) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.name)
                                        .font(.body)
                                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                                    Text(repo.path)
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.1, green: 0.11, blue: 0.15)))
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if !selectedPaths.isEmpty {
                    Text("\(selectedPaths.count) repo\(selectedPaths.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.70))
                }
                Button("Copy") {
                    onCopy(Array(selectedPaths))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(selectedPaths.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}

// MARK: - Scope Badge

private func mcpScopeBadge(_ scope: McpServer.McpScope) -> some View {
    Text(scope.rawValue)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .foregroundStyle(.white)
        .background(Capsule().fill(scope == .global
            ? Color(red: 0.48, green: 0.64, blue: 0.97) : Color.orange))
}

// MARK: - Server Row

private struct ServerRow: View {
    let server: McpServer
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                Text(server.command)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .lineLimit(1)
            }
            Spacer()
            mcpScopeBadge(server.scope)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Server Sheet

private struct CreateMcpServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""
    @State private var args = ""
    @State private var envKeys: [String] = []
    @State private var envVals: [String] = []
    @State private var scope: McpServer.McpScope = .global
    let onCreate: (McpServer) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("New MCP Server")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("my-server", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Command").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("/usr/local/bin/npx", text: $command).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Arguments (comma-separated)").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("-y, @modelcontextprotocol/server-name", text: $args).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Environment Variables").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Spacer()
                    Button { envKeys.append(""); envVals.append("") } label: {
                        Label("Add", systemImage: "plus.circle").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                }
                ForEach(envKeys.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("KEY", text: Binding(
                            get: { i < envKeys.count ? envKeys[i] : "" },
                            set: { if i < envKeys.count { envKeys[i] = $0 } }
                        )).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                        Text("=").foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                        TextField("value", text: Binding(
                            get: { i < envVals.count ? envVals[i] : "" },
                            set: { if i < envVals.count { envVals[i] = $0 } }
                        )).textFieldStyle(.roundedBorder)
                        Button {
                            if i < envKeys.count { envKeys.remove(at: i); envVals.remove(at: i) }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.7)) }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Scope").font(.caption).foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                Picker("Scope", selection: $scope) {
                    ForEach(McpServer.McpScope.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 200)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let parsedArgs = args.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    var env: [String: String] = [:]
                    for i in 0..<min(envKeys.count, envVals.count) {
                        let key = envKeys[i].trimmingCharacters(in: .whitespaces)
                        if !key.isEmpty { env[key] = envVals[i] }
                    }
                    let server = McpServer(name: name.trimmingCharacters(in: .whitespaces),
                                          command: command.trimmingCharacters(in: .whitespaces),
                                          args: parsedArgs, env: env, scope: scope)
                    onCreate(server)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 480)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}
