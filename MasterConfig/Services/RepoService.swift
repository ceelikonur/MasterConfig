import Foundation

@Observable
@MainActor
final class RepoService {
    var repos: [Repo] = []
    var isScanning = false
    var lastError: String?

    private let fm = FileManager.default
    private let scanPaths: [String]

    init(scanPaths: [String] = ["~/Desktop"]) {
        self.scanPaths = scanPaths
    }

    // MARK: - Scan

    func scanRepos() async {
        isScanning = true
        defer { isScanning = false }

        var found: [Repo] = []
        for rawPath in scanPaths {
            let expandedPath = (rawPath as NSString).expandingTildeInPath
            let base = URL(fileURLWithPath: expandedPath)
            let discovered = await discoverRepos(in: base, depth: 2)
            found.append(contentsOf: discovered)
        }
        repos = found.sorted { $0.name < $1.name }
    }

    private func discoverRepos(in directory: URL, depth: Int) async -> [Repo] {
        guard depth > 0 else { return [] }

        // Check if this dir itself is a repo
        if fm.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            if let repo = await loadRepo(at: directory) { return [repo] }
            return []
        }

        var result: [Repo] = []
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { return [] }

        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            if fm.fileExists(atPath: item.appendingPathComponent(".git").path) {
                if let repo = await loadRepo(at: item) {
                    result.append(repo)
                }
            } else if depth > 1 {
                let sub = await discoverRepos(in: item, depth: depth - 1)
                result.append(contentsOf: sub)
            }
        }
        return result
    }

    func loadRepo(at url: URL) async -> Repo? {
        let gitDir = url.appendingPathComponent(".git")
        guard fm.fileExists(atPath: gitDir.path) else { return nil }

        let branch = await runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: url.path).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = await runGit(["status", "--porcelain"], at: url.path)
        let status = parseStatus(statusOutput)
        let remoteURL = await runGit(["remote", "get-url", "origin"], at: url.path).trimmingCharacters(in: .whitespacesAndNewlines)
        let logOutput = await runGit(["log", "-1", "--pretty=format:%H|%h|%s|%an|%cd", "--date=format:%Y-%m-%d"], at: url.path)
        let lastCommit = parseCommit(logOutput)

        let claudeMDPath = url.appendingPathComponent("CLAUDE.md")
        let hasClaudeMD = fm.fileExists(atPath: claudeMDPath.path)
        let claudeMDContent = hasClaudeMD ? (try? String(contentsOf: claudeMDPath, encoding: .utf8)) : nil

        return Repo(
            path: url.path,
            name: url.lastPathComponent,
            branch: branch.isEmpty ? "unknown" : branch,
            status: status,
            remoteURL: remoteURL.isEmpty ? nil : remoteURL,
            hasClaudeMD: hasClaudeMD,
            claudeMDContent: claudeMDContent,
            lastCommit: lastCommit
        )
    }

    // MARK: - Git Operations

    func runGit(_ args: [String], at path: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: path)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    func gitLog(at path: String, count: Int = 20) async -> [Commit] {
        let output = await runGit(["log", "-\(count)", "--pretty=format:%H|%h|%s|%an|%cd", "--date=format:%Y-%m-%d"], at: path)
        return output.components(separatedBy: .newlines).compactMap { parseCommit($0) }
    }

    func gitDiff(at path: String) async -> String {
        await runGit(["diff", "--stat"], at: path)
    }

    func saveClaudeMD(content: String, repoPath: String) throws {
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent("CLAUDE.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Create Repo

    func createRepo(
        name: String,
        at parentPath: String,
        description: String,
        gitignoreTemplate: GitignoreTemplate,
        githubToken: String?,
        makeInitialCommit: Bool
    ) async throws -> Repo {
        let repoURL = URL(fileURLWithPath: parentPath).appendingPathComponent(name)

        // 1. Create directory
        try fm.createDirectory(at: repoURL, withIntermediateDirectories: true)

        // 2. git init
        _ = await runGit(["init"], at: repoURL.path)
        _ = await runGit(["checkout", "-b", "main"], at: repoURL.path)

        // 3. .gitignore
        let gitignoreContent = gitignoreTemplate.content
        if !gitignoreContent.isEmpty {
            try gitignoreContent.write(
                to: repoURL.appendingPathComponent(".gitignore"),
                atomically: true, encoding: .utf8
            )
        }

        // 4. CLAUDE.md
        let claudeMD = buildClaudeMD(name: name, description: description)
        try claudeMD.write(
            to: repoURL.appendingPathComponent("CLAUDE.md"),
            atomically: true, encoding: .utf8
        )

        // 5. .claude/ structure
        let claudeDir = repoURL.appendingPathComponent(".claude")
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // 6. GitHub MCP (if token provided)
        if let token = githubToken, !token.isEmpty {
            let mcpJSON: [String: Any] = [
                "mcpServers": [
                    "github": [
                        "command": "npx",
                        "args": ["-y", "@modelcontextprotocol/server-github"],
                        "env": ["GITHUB_PERSONAL_ACCESS_TOKEN": token]
                    ]
                ]
            ]
            let mcpData = try JSONSerialization.data(withJSONObject: mcpJSON, options: [.prettyPrinted, .sortedKeys])
            try mcpData.write(to: repoURL.appendingPathComponent(".mcp.json"))
        }

        // 7. Initial commit
        if makeInitialCommit {
            _ = await runGit(["add", "."], at: repoURL.path)
            _ = await runGit(["commit", "-m", "Initial commit — bootstrapped by MasterConfig"], at: repoURL.path)
        }

        // 8. Reload and return
        await scanRepos()
        if let found = repos.first(where: { $0.path == repoURL.path }) { return found }
        let loaded = await loadRepo(at: repoURL)
        return loaded!
    }

    private func buildClaudeMD(name: String, description: String) -> String {
        let desc = description.isEmpty ? "[Add a one-line description here]" : description
        return """
        # \(name)

        ## Project Overview
        \(desc)

        ## Development Commands
        ```bash
        # Add your commands here
        ```

        ## Code Conventions
        - [Add naming, file structure, and pattern conventions]

        ## Key Files
        - [List important files Claude should know about]

        ## On-Demand Context
        | Topic | Files to read |
        |-------|--------------|
        | [e.g., Models] | `src/models/` |
        | [e.g., Config] | `.env.example`, `src/config.ts` |

        ## Notes for Claude
        - [Add project-specific context, gotchas, and preferences]
        """
    }

    // MARK: - Parsers

    private func parseStatus(_ output: String) -> RepoStatus {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .clean }
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            if line.hasPrefix("UU") || line.hasPrefix("AA") { return .conflict }
        }
        let hasStaged = lines.contains { $0.first != " " && $0.first != "?" }
        let hasUntracked = lines.contains { $0.hasPrefix("??") }
        let hasModified = lines.contains { $0.first == " " && $0.count > 1 }
        if hasStaged { return .staged }
        if hasModified { return .modified }
        if hasUntracked { return .untracked }
        return .modified
    }

    private func parseCommit(_ line: String) -> Commit? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 5 else { return nil }
        return Commit(hash: parts[0], shortHash: parts[1], message: parts[2], author: parts[3], date: nil, dateString: parts[4])
    }
}
