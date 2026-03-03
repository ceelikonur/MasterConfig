import Foundation

// MARK: - Navigation

enum NavSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview   = "Overview"
    case repos      = "Repos"
    case skills     = "Skills"
    case agents     = "Agents"
    case plugins    = "Plugins"
    case mcp        = "MCP"
    case memory     = "Memory"
    case settings   = "Settings"
    case tasks      = "Tasks"
    case search     = "Search"
    case visualize  = "Visualize"
    case chat       = "Terminal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:  return "square.grid.2x2"
        case .repos:     return "folder.badge.gearshape"
        case .skills:    return "bolt.circle"
        case .agents:    return "person.crop.circle.badge.checkmark"
        case .plugins:   return "puzzlepiece.extension"
        case .mcp:       return "server.rack"
        case .memory:    return "brain"
        case .settings:  return "gearshape.2"
        case .tasks:     return "checklist"
        case .search:    return "magnifyingglass"
        case .visualize: return "scribble.variable"
        case .chat:      return "terminal"
        }
    }
}

// MARK: - Search

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let content: String
    let section: NavSection
    let filePath: String

    init(id: UUID = UUID(), title: String, subtitle: String, content: String, section: NavSection, filePath: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.section = section
        self.filePath = filePath
    }
}

// MARK: - Command Palette

struct PaletteCommand: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let icon: String
    let section: NavSection?
    let action: @Sendable () -> Void

    init(id: UUID = UUID(), title: String, subtitle: String = "", icon: String, section: NavSection? = nil, action: @Sendable @escaping () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.section = section
        self.action = action
    }

    static func == (lhs: PaletteCommand, rhs: PaletteCommand) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Preferences

struct AppPrefs: Codable, Sendable {
    var lastSelectedSection: String?
    var repoScanPaths: [String]
    var editorFontSize: Int
    var showHiddenFiles: Bool

    static let `default` = AppPrefs(
        lastSelectedSection: NavSection.overview.rawValue,
        repoScanPaths: ["~/Desktop"],
        editorFontSize: 14,
        showHiddenFiles: false
    )
}

// MARK: - Task Models

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var subject: String
    var description: String
    var status: TaskStatus
    var owner: String?
    var blockedBy: [String]

    enum TaskStatus: String, Codable, CaseIterable, Sendable {
        case pending    = "pending"
        case inProgress = "in_progress"
        case completed  = "completed"
        case deleted    = "deleted"

        var color: String {
            switch self {
            case .pending:    return "gray"
            case .inProgress: return "blue"
            case .completed:  return "green"
            case .deleted:    return "red"
            }
        }

        var label: String {
            switch self {
            case .pending:    return "Pending"
            case .inProgress: return "In Progress"
            case .completed:  return "Completed"
            case .deleted:    return "Deleted"
            }
        }
    }
}

struct TaskTeam: Identifiable, Codable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var members: [TeamMember]
}

struct TeamMember: Codable, Sendable {
    var name: String
    var agentId: String
    var agentType: String
}
