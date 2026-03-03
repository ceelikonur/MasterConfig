import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)

    static let statusGreen = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let statusYellow = Color(red: 0.88, green: 0.69, blue: 0.41)
    static let statusBlue = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let statusOrange = Color(red: 1.0, green: 0.62, blue: 0.39)
    static let statusRed = Color(red: 0.97, green: 0.47, blue: 0.56)
    static let statusGray = Color(red: 0.34, green: 0.37, blue: 0.54)

    static func forStatus(_ status: RepoStatus) -> Color {
        switch status {
        case .clean:     return .statusGreen
        case .modified:  return .statusYellow
        case .staged:    return .statusBlue
        case .untracked: return .statusOrange
        case .ahead:     return Color(red: 0.49, green: 0.84, blue: 0.87)
        case .behind:    return Color(red: 0.69, green: 0.53, blue: 0.87)
        case .conflict:  return .statusRed
        case .unknown:   return .statusGray
        }
    }
}

// MARK: - ReposView

struct ReposView: View {
    @Environment(RepoService.self) private var repoService
    @State private var selectedRepo: Repo?
    @State private var searchText = ""
    @State private var activeTab: RepoTab = .status
    @State private var gitStatusOutput = ""
    @State private var commits: [Commit] = []
    @State private var diffOutput = ""
    @State private var claudeMDContent = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSaveSuccess = false
    @State private var aheadCount = 0
    @State private var behindCount = 0
    @State private var claudeDirEntries: [ClaudeDirEntry] = []
    @State private var showCreateRepoSheet = false

    struct ClaudeDirEntry: Identifiable {
        var id: String { name }
        let name: String
        let isDirectory: Bool
    }

    enum RepoTab: String, CaseIterable {
        case status = "Status"
        case log = "Log"
        case claudemd = "CLAUDE.md"
        case diff = "Diff"
    }

    private var filteredRepos: [Repo] {
        if searchText.isEmpty { return repoService.repos }
        let q = searchText.lowercased()
        return repoService.repos.filter {
            $0.name.lowercased().contains(q) || $0.branch.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            repoListPanel
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detailPanel
                .frame(minWidth: 400)
        }
        .background(Color.bgPrimary)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showCreateRepoSheet) {
            CreateRepoSheet { name, parentPath, description, gitignore, githubToken, makeCommit in
                Task {
                    do {
                        let repo = try await repoService.createRepo(
                            name: name,
                            at: parentPath,
                            description: description,
                            gitignoreTemplate: gitignore,
                            githubToken: githubToken.isEmpty ? nil : githubToken,
                            makeInitialCommit: makeCommit
                        )
                        selectedRepo = repo
                        activeTab = .status
                        if let r = repos.first(where: { $0.path == repo.path }) {
                            await loadRepoDetails(r)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
        .task {
            if repoService.repos.isEmpty {
                await repoService.scanRepos()
            }
        }
    }

    private var repos: [Repo] { repoService.repos }

    // MARK: - Left Panel

    private var repoListPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Filter repos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(10)
            .background(Color.surface)
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if repoService.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 8)
            }

            List(filteredRepos, id: \.id, selection: $selectedRepo) { repo in
                repoRow(repo)
                    .tag(repo)
                    .listRowBackground(
                        selectedRepo?.id == repo.id
                            ? Color.accent.opacity(0.15)
                            : Color.clear
                    )
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedRepo) { _, newRepo in
                if let repo = newRepo {
                    activeTab = .status
                    Task { await loadRepoDetails(repo) }
                }
            }
        }
        .background(Color.bgPrimary)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showCreateRepoSheet = true
                } label: {
                    Label("New Repo", systemImage: "plus")
                }
                .help("Create a new repository")

                Button {
                    Task { await repoService.scanRepos() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh repos")
            }
        }
    }

    private func repoRow(_ repo: Repo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.forStatus(repo.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let commit = repo.lastCommit {
                    Text(commit.message)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(repo.branch)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accent.opacity(0.15))
                .foregroundStyle(Color.accent)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Right Panel

    private var detailPanel: some View {
        Group {
            if let repo = selectedRepo {
                VStack(spacing: 0) {
                    repoHeader(repo)
                    tabBar
                    Divider().background(Color.textSecondary.opacity(0.3))
                    tabContent(repo)
                    Spacer(minLength: 0)
                    bottomToolbar(repo)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textSecondary)
                    Text("Select a repository")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgPrimary)
    }

    private func repoHeader(_ repo: Repo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name)
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption)
                        Text(repo.path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(Color.textSecondary)

                    if let remote = repo.remoteURL {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(remote)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Branch badge
                    Label(repo.branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accent.opacity(0.15))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(6)

                    // Ahead/Behind badges
                    if aheadCount > 0 {
                        Text("↑\(aheadCount)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.49, green: 0.84, blue: 0.87).opacity(0.15))
                            .foregroundStyle(Color(red: 0.49, green: 0.84, blue: 0.87))
                            .cornerRadius(6)
                    }
                    if behindCount > 0 {
                        Text("↓\(behindCount)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.69, green: 0.53, blue: 0.87).opacity(0.15))
                            .foregroundStyle(Color(red: 0.69, green: 0.53, blue: 0.87))
                            .cornerRadius(6)
                    }

                    // Status badge
                    Text(repo.status.label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.forStatus(repo.status).opacity(0.15))
                        .foregroundStyle(Color.forStatus(repo.status))
                        .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RepoTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(.subheadline, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundStyle(activeTab == tab ? Color.accent : Color.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if activeTab == tab {
                        Rectangle()
                            .fill(Color.accent)
                            .frame(height: 2)
                    }
                }
            }
            Spacer()
        }
        .background(Color.surface)
    }

    @ViewBuilder
    private func tabContent(_ repo: Repo) -> some View {
        switch activeTab {
        case .status:
            statusTab(repo)
        case .log:
            logTab
        case .claudemd:
            claudeMDTab(repo)
        case .diff:
            diffTab
        }
    }

    // MARK: - Tabs

    private func statusTab(_ repo: Repo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if gitStatusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusGreen)
                        Text("Working tree clean")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding()
                } else {
                    Text("Changed files:")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.bottom, 4)

                    let lines = gitStatusOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) {
                            let prefix = String(line.prefix(2))
                            statusIcon(prefix)
                            Text(line.dropFirst(3))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }

                // .claude/ directory listing
                if !claudeDirEntries.isEmpty {
                    Divider().background(Color.textSecondary.opacity(0.3))
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accent)
                        Text(".claude/")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(claudeDirEntries) { entry in
                                HStack(spacing: 4) {
                                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                                        .font(.caption2)
                                    Text(entry.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.surface)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusIcon(_ prefix: String) -> some View {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        let (icon, color): (String, Color) = {
            if trimmed.contains("M") { return ("pencil.circle.fill", .statusYellow) }
            if trimmed.contains("A") { return ("plus.circle.fill", .statusGreen) }
            if trimmed.contains("D") { return ("minus.circle.fill", .statusRed) }
            if trimmed.contains("?") { return ("questionmark.circle.fill", .statusOrange) }
            if trimmed.contains("U") { return ("exclamationmark.triangle.fill", .statusRed) }
            return ("circle.fill", .statusGray)
        }()

        return Image(systemName: icon)
            .foregroundStyle(color)
            .font(.caption)
    }

    private var logTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if commits.isEmpty {
                    Text("No commits found")
                        .foregroundStyle(Color.textSecondary)
                        .padding(16)
                } else {
                    ForEach(Array(commits.enumerated()), id: \.offset) { _, commit in
                        HStack(spacing: 12) {
                            Text(commit.shortHash)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.accent)
                                .frame(width: 60, alignment: .leading)

                            Text(commit.message)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(commit.author)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)

                            Text(commit.dateString)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if commit.hash != commits.last?.hash {
                            Divider()
                                .background(Color.textSecondary.opacity(0.2))
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func claudeMDTab(_ repo: Repo) -> some View {
        if repo.hasClaudeMD {
            VStack(spacing: 0) {
                WebEditorView(
                    content: $claudeMDContent,
                    language: "markdown",
                    isReadOnly: false,
                    onSave: { saveClaudeMD(repoPath: repo.path) }
                )

                HStack {
                    Spacer()
                    if showSaveSuccess {
                        Text("Saved!")
                            .font(.caption)
                            .foregroundStyle(Color.statusGreen)
                            .transition(.opacity)
                    }
                    Button {
                        saveClaudeMD(repoPath: repo.path)
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                }
                .padding(12)
                .background(Color.surface)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.textSecondary)
                Text("No CLAUDE.md in this repo")
                    .foregroundStyle(Color.textSecondary)
                Button {
                    claudeMDContent = "# CLAUDE.md\n\n"
                    createClaudeMD(repoPath: repo.path)
                } label: {
                    Label("Create CLAUDE.md", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var diffTab: some View {
        ScrollView {
            if diffOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No changes to diff")
                    .foregroundStyle(Color.textSecondary)
                    .padding(16)
            } else {
                Text(diffOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Bottom Toolbar

    private func bottomToolbar(_ repo: Repo) -> some View {
        HStack(spacing: 12) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                openInTerminal(path: repo.path)
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)

            Button {
                openInClaude(path: repo.path)
            } label: {
                Label("Claude", systemImage: "sparkle")
            }
            .buttonStyle(.bordered)

            Button {
                openInEditor(path: repo.path)
            } label: {
                Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.bordered)

            Spacer()

            if repo.hasClaudeMD {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.accent)
                    .help("Has CLAUDE.md")
            }
        }
        .padding(12)
        .background(Color.surface)
    }

    // MARK: - Actions

    private func loadRepoDetails(_ repo: Repo) async {
        gitStatusOutput = await repoService.runGit(["status", "--porcelain"], at: repo.path)
        commits = await repoService.gitLog(at: repo.path, count: 30)
        diffOutput = await repoService.gitDiff(at: repo.path)
        claudeMDContent = repo.claudeMDContent ?? ""

        // Ahead/behind counts
        let aheadStr = await repoService.runGit(["rev-list", "@{upstream}..HEAD", "--count"], at: repo.path)
        let behindStr = await repoService.runGit(["rev-list", "HEAD..@{upstream}", "--count"], at: repo.path)
        aheadCount = Int(aheadStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        behindCount = Int(behindStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // .claude/ directory listing
        claudeDirEntries = loadClaudeDirEntries(repoPath: repo.path)
    }

    private func saveClaudeMD(repoPath: String) {
        do {
            try repoService.saveClaudeMD(content: claudeMDContent, repoPath: repoPath)
            showSaveSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showSaveSuccess = false
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func createClaudeMD(repoPath: String) {
        do {
            try repoService.saveClaudeMD(content: claudeMDContent, repoPath: repoPath)
            Task { await repoService.scanRepos() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func openInTerminal(path: String) {
        let script = """
            tell application "Terminal"
                do script "cd \(path.replacingOccurrences(of: "\"", with: "\\\""))"
                activate
            end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func openInEditor(path: String) {
        let editors: [(app: String, name: String)] = [
            ("/Applications/Cursor.app", "Cursor"),
            ("/Applications/Visual Studio Code.app", "Visual Studio Code"),
            ("/Applications/Sublime Text.app", "Sublime Text"),
        ]
        let repoURL = URL(fileURLWithPath: path)
        for editor in editors {
            let editorURL = URL(fileURLWithPath: editor.app)
            if FileManager.default.fileExists(atPath: editor.app) {
                NSWorkspace.shared.open(
                    [repoURL],
                    withApplicationAt: editorURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }
        // Fallback: open in Finder
        NSWorkspace.shared.open(repoURL)
    }

    private func loadClaudeDirEntries(repoPath: String) -> [ClaudeDirEntry] {
        let claudeDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".claude")
        guard FileManager.default.fileExists(atPath: claudeDir.path) else { return [] }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return ClaudeDirEntry(name: url.lastPathComponent, isDirectory: isDir)
        }.sorted { $0.name < $1.name }
    }

    private func openInClaude(path: String) {
        let script = """
            tell application "Terminal"
                do script "cd \(path.replacingOccurrences(of: "\"", with: "\\\"")) && claude"
                activate
            end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Create Repo Sheet

private struct CreateRepoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String, GitignoreTemplate, String, Bool) -> Void

    @State private var repoName = ""
    @State private var parentPath = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    @State private var description = ""
    @State private var gitignoreTemplate: GitignoreTemplate = .node
    @State private var addGitHub = false
    @State private var githubToken = ""
    @State private var makeInitialCommit = true
    @State private var isCreating = false

    private var isValid: Bool {
        !repoName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Repository")
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)
                    Text("Bootstrap a new local repo with CLAUDE.md and git init")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(24)
            .background(Color.surface)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Name
                    field(label: "Repository Name", required: true) {
                        TextField("my-awesome-project", text: $repoName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: repoName) { _, v in
                                repoName = v.lowercased()
                                    .replacingOccurrences(of: " ", with: "-")
                                    .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                            }
                    }

                    // Location
                    field(label: "Location") {
                        HStack {
                            Text(parentPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                            Button("Browse...") {
                                chooseFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                        if !repoName.isEmpty {
                            Text("→ \(parentPath)/\(repoName)/")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    // Description
                    field(label: "Description (goes into CLAUDE.md)") {
                        TextField("What does this project do?", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    // .gitignore
                    field(label: ".gitignore Template") {
                        Picker("Template", selection: $gitignoreTemplate) {
                            ForEach(GitignoreTemplate.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().opacity(0.3)

                    // GitHub MCP
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $addGitHub) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .foregroundStyle(Color.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add GitHub MCP")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Creates .mcp.json with GitHub server so Claude can access this repo's issues, PRs, and code")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)

                        if addGitHub {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("GITHUB_PERSONAL_ACCESS_TOKEN")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.orange.opacity(0.9))
                                    Spacer()
                                    Text("github.com/settings/tokens → New token (repo scope)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $githubToken)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                        }
                    }

                    Divider().opacity(0.3)

                    // Options
                    Toggle(isOn: $makeInitialCommit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create initial commit")
                                .foregroundStyle(Color.textPrimary)
                            Text("Commits .gitignore, CLAUDE.md, and .mcp.json (if any)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)

                    // Preview
                    if !repoName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What will be created:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            VStack(alignment: .leading, spacing: 4) {
                                previewRow("folder", "\(repoName)/", color: Color.accent)
                                previewRow("doc.text", "\(repoName)/CLAUDE.md", color: Color(red: 0.62, green: 0.81, blue: 0.42))
                                previewRow("folder", "\(repoName)/.claude/", color: Color.accent)
                                if gitignoreTemplate != .none {
                                    previewRow("doc", "\(repoName)/.gitignore (\(gitignoreTemplate.rawValue))", color: Color.textSecondary)
                                }
                                if addGitHub && !githubToken.isEmpty {
                                    previewRow("server.rack", "\(repoName)/.mcp.json (GitHub)", color: Color(red: 0.48, green: 0.84, blue: 0.87))
                                }
                                if makeInitialCommit {
                                    previewRow("clock.arrow.circlepath", "Initial commit on main", color: Color.textSecondary)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                        }
                    }
                }
                .padding(24)
            }

            Divider().opacity(0.3)

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    guard isValid else { return }
                    isCreating = true
                    onCreate(
                        repoName.trimmingCharacters(in: .whitespaces),
                        parentPath,
                        description,
                        gitignoreTemplate,
                        addGitHub ? githubToken : "",
                        makeInitialCommit
                    )
                    dismiss()
                } label: {
                    if isCreating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Creating...")
                        }
                    } else {
                        Label("Create Repository", systemImage: "folder.badge.plus")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(!isValid || isCreating)
            }
            .padding(16)
            .background(Color.surface)
        }
        .frame(width: 560)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    private func field<C: View>(label: String, required: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                if required {
                    Text("*").foregroundStyle(Color.accent).font(.caption)
                }
            }
            content()
        }
    }

    private func previewRow(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 14)
            Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.textPrimary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: parentPath)
        panel.prompt = "Choose Location"
        if panel.runModal() == .OK, let url = panel.url {
            parentPath = url.path
        }
    }
}
