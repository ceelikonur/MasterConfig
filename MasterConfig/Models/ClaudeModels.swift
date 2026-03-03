import Foundation

// MARK: - Skill

struct Skill: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var content: String          // Full SKILL.md content
    var directoryPath: String    // ~/.claude/skills/<name>/

    // Parsed from YAML frontmatter
    var frontmatter: [String: String]

    static func empty() -> Skill {
        Skill(name: "new-skill", description: "", content: "---\nname: new-skill\ndescription: \"\"\n---\n\n# New Skill\n\n", directoryPath: "", frontmatter: [:])
    }
}

// MARK: - Agent

struct Agent: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var model: String
    var tools: [String]
    var content: String          // Full .md content
    var filePath: String         // ~/.claude/agents/<name>.md
    var isGlobal: Bool           // vs per-repo

    static func empty() -> Agent {
        Agent(name: "new-agent", description: "", model: "claude-sonnet-4-6", tools: [], content: "---\nname: new-agent\ndescription: \"\"\nmodel: claude-sonnet-4-6\ntools: []\n---\n\n# New Agent\n\n", filePath: "", isGlobal: true)
    }
}

// MARK: - MCP Server

struct McpServer: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var scope: McpScope

    enum McpScope: String, Codable, CaseIterable, Sendable {
        case global = "global"
        case local = "local"
    }
}

// MARK: - Plugin

struct Plugin: Identifiable, Hashable, Sendable {
    var id: String { directoryPath }
    let name: String
    let marketplaceName: String
    let directoryPath: String
    let isOfficial: Bool
    let readme: String
    let skills: [PluginSkill]
}

struct PluginSkill: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    var content: String
}

// MARK: - Memory File

struct MemoryFile: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var displayName: String
    var content: String
    var isGlobal: Bool
    var projectSlug: String?
}

// MARK: - Claude Project

struct ClaudeProject: Identifiable, Codable, Hashable, Sendable {
    var id: String { slug }
    var slug: String
    var memoryFiles: [MemoryFile]
    var lastModified: Date?
}

// MARK: - Claude Settings

struct ClaudeSettings: Codable, Sendable {
    var model: String?
    var permissions: Permissions?
    var env: [String: String]?

    struct Permissions: Codable, Sendable {
        var allow: [String]?
        var deny: [String]?
    }
}
