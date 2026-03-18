import Foundation

// MARK: - Agent Instance

struct AgentInstance: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String                    // e.g. "api-server"
    var repoPath: String               // full path to repo
    var repoName: String               // just the folder name
    var processRef: String             // PID string for tracking
    var status: AgentStatus
    var currentTask: String?
    var spawnedAt: Date
    var lastActivity: Date
    var messageCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        repoName: String = "",
        processRef: String = "",
        status: AgentStatus = .starting,
        currentTask: String? = nil,
        spawnedAt: Date = Date(),
        lastActivity: Date = Date(),
        messageCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.repoName = repoName.isEmpty ? URL(fileURLWithPath: repoPath).lastPathComponent : repoName
        self.processRef = processRef
        self.status = status
        self.currentTask = currentTask
        self.spawnedAt = spawnedAt
        self.lastActivity = lastActivity
        self.messageCount = messageCount
    }
}

// MARK: - Agent Status

enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case starting   = "starting"
    case idle       = "idle"
    case working    = "working"
    case blocked    = "blocked"
    case completed  = "completed"
    case dead       = "dead"
    case orphan     = "orphan"

    var label: String {
        switch self {
        case .starting:  return "Starting"
        case .idle:      return "Idle"
        case .working:   return "Working"
        case .blocked:   return "Blocked"
        case .completed: return "Completed"
        case .dead:      return "Dead"
        case .orphan:    return "Orphan"
        }
    }

    var color: String {
        switch self {
        case .starting:  return "orange"
        case .idle:      return "gray"
        case .working:   return "blue"
        case .blocked:   return "red"
        case .completed: return "green"
        case .dead:      return "red"
        case .orphan:    return "yellow"
        }
    }

    var icon: String {
        switch self {
        case .starting:  return "arrow.clockwise.circle"
        case .idle:      return "pause.circle"
        case .working:   return "play.circle.fill"
        case .blocked:   return "exclamationmark.triangle"
        case .completed: return "checkmark.circle.fill"
        case .dead:      return "xmark.circle"
        case .orphan:    return "questionmark.circle"
        }
    }
}

// MARK: - Agent Message

struct AgentMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let from: String
    let to: String
    let content: String
    let messageType: MessageType

    enum MessageType: String, Codable, CaseIterable, Sendable {
        case task       = "task"
        case result     = "result"
        case context    = "context"
        case question   = "question"
        case status     = "status"
        case shutdown   = "shutdown"
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        from: String,
        to: String,
        content: String,
        messageType: MessageType
    ) {
        self.id = id
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.content = content
        self.messageType = messageType
    }
}

// MARK: - Orchestrator State

struct OrchestratorState: Codable, Hashable, Sendable {
    var sessionId: UUID
    var teamName: String
    var agents: [AgentInstance]
    var mainSessionMode: MainSessionMode
    var leadAgentPID: String?          // PID of lead agent process
    var leadAgentStatus: AgentStatus?  // Lead agent status
    var createdAt: Date
    var lastSaved: Date

    enum MainSessionMode: String, Codable, CaseIterable, Sendable {
        case embedded = "embedded"
        case iterm    = "iterm"
    }

    init(
        sessionId: UUID = UUID(),
        teamName: String = "default",
        agents: [AgentInstance] = [],
        mainSessionMode: MainSessionMode = .iterm,
        leadAgentPID: String? = nil,
        leadAgentStatus: AgentStatus? = nil,
        createdAt: Date = Date(),
        lastSaved: Date = Date()
    ) {
        self.sessionId = sessionId
        self.teamName = teamName
        self.agents = agents
        self.mainSessionMode = mainSessionMode
        self.leadAgentPID = leadAgentPID
        self.leadAgentStatus = leadAgentStatus
        self.createdAt = createdAt
        self.lastSaved = lastSaved
    }
}
