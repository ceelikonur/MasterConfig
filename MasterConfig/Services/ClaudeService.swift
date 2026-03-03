import Foundation

@Observable
@MainActor
final class ClaudeService {
    var skills: [Skill] = []
    var agents: [Agent] = []
    var mcpServers: [McpServer] = []
    var memoryFiles: [MemoryFile] = []
    var claudeProjects: [ClaudeProject] = []
    var plugins: [Plugin] = []
    var globalSettings: ClaudeSettings = ClaudeSettings()
    var isLoading = false
    var lastError: String?

    private let fm = FileManager.default
    private let claudeRoot: URL

    init() {
        claudeRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    }

    // MARK: - Load All

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        async let s: () = loadSkills()
        async let a: () = loadAgents()
        async let m: () = loadMCPServers()
        async let mem: () = loadMemoryFiles()
        async let set: () = loadSettings()
        async let p: () = loadPlugins()
        _ = await (s, a, m, mem, set, p)
    }

    // MARK: - Plugins

    func loadPlugins() async {
        let marketplacesDir = claudeRoot.appendingPathComponent("plugins/marketplaces")
        guard fm.fileExists(atPath: marketplacesDir.path),
              let marketplaces = try? fm.contentsOfDirectory(at: marketplacesDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { plugins = []; return }

        var result: [Plugin] = []
        for marketplace in marketplaces where marketplace.hasDirectoryPath {
            let marketplaceName = marketplace.lastPathComponent
            for subdir in ["plugins", "external_plugins"] {
                let pluginsDir = marketplace.appendingPathComponent(subdir)
                guard fm.fileExists(atPath: pluginsDir.path),
                      let pluginDirs = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                else { continue }

                for pluginDir in pluginDirs where pluginDir.hasDirectoryPath {
                    let isOfficial = subdir == "plugins"
                    let readme = (try? String(contentsOf: pluginDir.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
                    let skillsDir = pluginDir.appendingPathComponent("skills")
                    var skills: [PluginSkill] = []
                    if let skillFiles = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                        for skillFile in skillFiles where skillFile.pathExtension == "md" || skillFile.lastPathComponent.hasSuffix("SKILL.md") {
                            let content = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
                            skills.append(PluginSkill(name: skillFile.deletingPathExtension().lastPathComponent, path: skillFile.path, content: content))
                        }
                    }
                    result.append(Plugin(name: pluginDir.lastPathComponent, marketplaceName: marketplaceName, directoryPath: pluginDir.path, isOfficial: isOfficial, readme: readme, skills: skills))
                }
            }
        }
        plugins = result.sorted { $0.name < $1.name }
    }

    // MARK: - Skills

    func loadSkills() async {
        let skillsURL = claudeRoot.appendingPathComponent("skills")
        guard fm.fileExists(atPath: skillsURL.path) else { skills = []; return }
        do {
            let dirs = try fm.contentsOfDirectory(at: skillsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            var result: [Skill] = []
            for dir in dirs where dir.hasDirectoryPath {
                let skillFile = dir.appendingPathComponent("SKILL.md")
                if fm.fileExists(atPath: skillFile.path),
                   let content = try? String(contentsOf: skillFile, encoding: .utf8) {
                    let fm = parseFrontmatter(content)
                    let skill = Skill(
                        name: fm["name"] ?? dir.lastPathComponent,
                        description: fm["description"] ?? "",
                        content: content,
                        directoryPath: dir.path,
                        frontmatter: fm
                    )
                    result.append(skill)
                }
            }
            skills = result.sorted { $0.name < $1.name }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveSkill(_ skill: Skill) async throws {
        let dirURL: URL
        if skill.directoryPath.isEmpty {
            dirURL = claudeRoot.appendingPathComponent("skills").appendingPathComponent(skill.name)
        } else {
            dirURL = URL(fileURLWithPath: skill.directoryPath)
        }
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent("SKILL.md")
        try skill.content.write(to: fileURL, atomically: true, encoding: .utf8)
        await loadSkills()
    }

    func deleteSkill(_ skill: Skill) async throws {
        let dirURL = URL(fileURLWithPath: skill.directoryPath)
        try fm.removeItem(at: dirURL)
        await loadSkills()
    }

    // MARK: - Agents

    func loadAgents() async {
        var result: [Agent] = []
        // Global agents
        let globalDir = claudeRoot.appendingPathComponent("agents")
        if fm.fileExists(atPath: globalDir.path) {
            if let files = try? fm.contentsOfDirectory(at: globalDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for file in files where file.pathExtension == "md" {
                    if let agent = parseAgent(at: file, isGlobal: true) {
                        result.append(agent)
                    }
                }
            }
        }
        agents = result.sorted { $0.name < $1.name }
    }

    func saveAgent(_ agent: Agent) async throws {
        let dirURL = agent.isGlobal
            ? claudeRoot.appendingPathComponent("agents")
            : URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".claude/agents")
        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL: URL
        if agent.filePath.isEmpty {
            fileURL = dirURL.appendingPathComponent(agent.name + ".md")
        } else {
            fileURL = URL(fileURLWithPath: agent.filePath)
        }
        try agent.content.write(to: fileURL, atomically: true, encoding: .utf8)
        await loadAgents()
    }

    func deleteAgent(_ agent: Agent) async throws {
        let fileURL = URL(fileURLWithPath: agent.filePath)
        try fm.removeItem(at: fileURL)
        await loadAgents()
    }

    // MARK: - MCP Servers

    func loadMCPServers() async {
        let mcpFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        guard fm.fileExists(atPath: mcpFile.path),
              let data = try? Data(contentsOf: mcpFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            mcpServers = []
            return
        }
        var result: [McpServer] = []
        for (name, value) in servers {
            guard let config = value as? [String: Any] else { continue }
            let command = config["command"] as? String ?? ""
            let args = config["args"] as? [String] ?? []
            let env = config["env"] as? [String: String] ?? [:]
            result.append(McpServer(name: name, command: command, args: args, env: env, scope: .global))
        }
        mcpServers = result.sorted { $0.name < $1.name }
    }

    func saveMCPServer(_ server: McpServer) async throws {
        let mcpFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        var json: [String: Any] = [:]
        if fm.fileExists(atPath: mcpFile.path),
           let data = try? Data(contentsOf: mcpFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        servers[server.name] = [
            "command": server.command,
            "args": server.args,
            "env": server.env
        ]
        json["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: mcpFile)
        await loadMCPServers()
    }

    func deleteMCPServer(_ server: McpServer) async throws {
        let mcpFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        guard fm.fileExists(atPath: mcpFile.path),
              let data = try? Data(contentsOf: mcpFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var servers = json["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: server.name)
        json["mcpServers"] = servers
        let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: mcpFile)
        await loadMCPServers()
    }

    // MARK: - Memory Files

    func loadMemoryFiles() async {
        var result: [MemoryFile] = []

        // Global CLAUDE.md
        let globalMD = claudeRoot.appendingPathComponent("CLAUDE.md")
        if let content = try? String(contentsOf: globalMD, encoding: .utf8) {
            result.append(MemoryFile(path: globalMD.path, displayName: "CLAUDE.md (Global)", content: content, isGlobal: true, projectSlug: nil))
        }

        // Per-project memory files
        let projectsDir = claudeRoot.appendingPathComponent("projects")
        if let slugDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for slugDir in slugDirs where slugDir.hasDirectoryPath {
                let memDir = slugDir.appendingPathComponent("memory")
                if let memFiles = try? fm.contentsOfDirectory(at: memDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                    for memFile in memFiles where memFile.pathExtension == "md" || memFile.lastPathComponent == "MEMORY.md" {
                        if let content = try? String(contentsOf: memFile, encoding: .utf8) {
                            result.append(MemoryFile(
                                path: memFile.path,
                                displayName: "\(slugDir.lastPathComponent)/\(memFile.lastPathComponent)",
                                content: content,
                                isGlobal: false,
                                projectSlug: slugDir.lastPathComponent
                            ))
                        }
                    }
                }
            }
        }
        memoryFiles = result
    }

    func saveMemoryFile(_ file: MemoryFile) async throws {
        let url = URL(fileURLWithPath: file.path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.content.write(to: url, atomically: true, encoding: .utf8)
        await loadMemoryFiles()
    }

    // MARK: - Settings

    func loadSettings() async {
        let settingsFile = claudeRoot.appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: settingsFile.path),
              let data = try? Data(contentsOf: settingsFile) else {
            globalSettings = ClaudeSettings()
            return
        }
        globalSettings = (try? JSONDecoder().decode(ClaudeSettings.self, from: data)) ?? ClaudeSettings()
    }

    func saveSettings(_ settings: ClaudeSettings) async throws {
        let settingsFile = claudeRoot.appendingPathComponent("settings.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFile)
        globalSettings = settings
    }

    func rawSettingsContent() -> String {
        let settingsFile = claudeRoot.appendingPathComponent("settings.json")
        return (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "{}"
    }

    func saveRawSettings(_ raw: String) async throws {
        let settingsFile = claudeRoot.appendingPathComponent("settings.json")
        guard let _ = try? JSONSerialization.jsonObject(with: raw.data(using: .utf8) ?? Data()) else {
            throw AppError.invalidJSON
        }
        try raw.write(to: settingsFile, atomically: true, encoding: .utf8)
        await loadSettings()
    }

    // MARK: - Search

    func search(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        var results: [SearchResult] = []

        for skill in skills {
            if skill.name.lowercased().contains(q) || skill.description.lowercased().contains(q) || skill.content.lowercased().contains(q) {
                results.append(SearchResult(title: skill.name, subtitle: "Skill", content: skill.description, section: .skills, filePath: skill.directoryPath))
            }
        }
        for agent in agents {
            if agent.name.lowercased().contains(q) || agent.description.lowercased().contains(q) || agent.content.lowercased().contains(q) {
                results.append(SearchResult(title: agent.name, subtitle: "Agent", content: agent.description, section: .agents, filePath: agent.filePath))
            }
        }
        for mem in memoryFiles {
            if mem.displayName.lowercased().contains(q) || mem.content.lowercased().contains(q) {
                results.append(SearchResult(title: mem.displayName, subtitle: "Memory", content: String(mem.content.prefix(200)), section: .memory, filePath: mem.path))
            }
        }
        return results
    }

    // MARK: - Helpers

    private func parseAgent(at url: URL, isGlobal: Bool) -> Agent? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fm = parseFrontmatter(content)
        let name = fm["name"] ?? url.deletingPathExtension().lastPathComponent
        let model = fm["model"] ?? "claude-sonnet-4-6"
        let toolsStr = fm["tools"] ?? ""
        let tools = toolsStr.isEmpty ? [] : toolsStr
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return Agent(name: name, description: fm["description"] ?? "", model: model, tools: tools, content: content, filePath: url.path, isGlobal: isGlobal)
    }

    func parseFrontmatter(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return result }
        var inFrontmatter = false
        for (i, line) in lines.enumerated() {
            if i == 0 { inFrontmatter = true; continue }
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if inFrontmatter, let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                result[key] = val
            }
        }
        return result
    }
}

enum AppError: LocalizedError {
    case invalidJSON
    case fileNotFound(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Invalid JSON format"
        case .fileNotFound(let p): return "File not found: \(p)"
        case .permissionDenied: return "Permission denied"
        }
    }
}
