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
    case chat         = "Terminal"
    case orchestrator = "Orchestrator"
    case costs        = "Costs"
    case approvals    = "Approvals"
    case orgChart     = "Org Chart"
    case routines     = "Routines"
    case activity     = "Activity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:     return "square.grid.2x2"
        case .repos:        return "folder.badge.gearshape"
        case .skills:       return "bolt.circle"
        case .agents:       return "person.crop.circle.badge.checkmark"
        case .plugins:      return "puzzlepiece.extension"
        case .mcp:          return "server.rack"
        case .memory:       return "brain"
        case .settings:     return "gearshape.2"
        case .tasks:        return "checklist"
        case .search:       return "magnifyingglass"
        case .visualize:    return "scribble.variable"
        case .chat:         return "terminal"
        case .orchestrator: return "network"
        case .costs:        return "dollarsign.circle"
        case .approvals:    return "checkmark.shield"
        case .orgChart:     return "person.3"
        case .routines:     return "clock.arrow.2.circlepath"
        case .activity:     return "list.bullet.rectangle"
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

// MARK: - Hierarchy: Enums

enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active    = "active"
    case completed = "completed"
    case archived  = "archived"
}

enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active    = "active"
    case paused    = "paused"
    case completed = "completed"
    case archived  = "archived"
}

enum MilestoneStatus: String, Codable, CaseIterable, Sendable {
    case open   = "open"
    case closed = "closed"
}

enum IssueStatus: String, Codable, CaseIterable, Sendable {
    case backlog    = "backlog"
    case todo       = "todo"
    case inProgress = "in_progress"
    case review     = "review"
    case done       = "done"

    var label: String {
        switch self {
        case .backlog:    return "Backlog"
        case .todo:       return "Todo"
        case .inProgress: return "In Progress"
        case .review:     return "Review"
        case .done:       return "Done"
        }
    }

    var icon: String {
        switch self {
        case .backlog:    return "tray"
        case .todo:       return "circle"
        case .inProgress: return "play.circle.fill"
        case .review:     return "eye.circle"
        case .done:       return "checkmark.circle.fill"
        }
    }
}

enum IssuePriority: String, Codable, CaseIterable, Sendable {
    case low    = "low"
    case normal = "normal"
    case high   = "high"
    case urgent = "urgent"

    var label: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down"
        case .normal: return "minus"
        case .high:   return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }
}

// MARK: - Hierarchy: Top-level container (stored in hierarchy.json)

struct TaskHierarchy: Codable, Sendable {
    var goals: [Goal]
    var milestones: [Milestone]

    init(goals: [Goal] = [], milestones: [Milestone] = []) {
        self.goals = goals
        self.milestones = milestones
    }
}

// MARK: - Hierarchy: Models

struct Goal: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String
    var status: GoalStatus
    var projectIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        status: GoalStatus = .active,
        projectIds: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.description = description
        self.status = status; self.projectIds = projectIds
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct Project: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String
    var goalId: String?
    var milestoneIds: [String]
    var status: ProjectStatus
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        goalId: String? = nil,
        milestoneIds: [String] = [],
        status: ProjectStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.description = description
        self.goalId = goalId; self.milestoneIds = milestoneIds
        self.status = status; self.createdAt = createdAt
    }
}

struct Milestone: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var projectId: String
    var issueIds: [String]
    var dueDate: Date?
    var status: MilestoneStatus

    init(
        id: String = UUID().uuidString,
        title: String,
        projectId: String,
        issueIds: [String] = [],
        dueDate: Date? = nil,
        status: MilestoneStatus = .open
    ) {
        self.id = id; self.title = title; self.projectId = projectId
        self.issueIds = issueIds; self.dueDate = dueDate; self.status = status
    }
}

struct Issue: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String
    var milestoneId: String?
    var projectId: String?
    var parentIssueId: String?
    var assignee: String?
    var status: IssueStatus
    var priority: IssuePriority
    var labels: [String]
    var comments: [IssueComment]
    var attachments: [String]
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        milestoneId: String? = nil,
        projectId: String? = nil,
        parentIssueId: String? = nil,
        assignee: String? = nil,
        status: IssueStatus = .backlog,
        priority: IssuePriority = .normal,
        labels: [String] = [],
        comments: [IssueComment] = [],
        attachments: [String] = [],
        createdBy: String = "board",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.description = description
        self.milestoneId = milestoneId; self.projectId = projectId
        self.parentIssueId = parentIssueId; self.assignee = assignee
        self.status = status; self.priority = priority; self.labels = labels
        self.comments = comments; self.attachments = attachments
        self.createdBy = createdBy; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct IssueComment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var author: String
    var body: String
    var createdAt: Date

    init(id: String = UUID().uuidString, author: String, body: String, createdAt: Date = Date()) {
        self.id = id; self.author = author; self.body = body; self.createdAt = createdAt
    }
}

// MARK: - Issue Context (for filtering in UI)

enum IssueContext: Hashable, Sendable {
    case all
    case goal(String)
    case project(String)
    case milestone(String)
}

// MARK: - Budget & Cost Models

struct BudgetConfig: Codable, Sendable {
    var monthlyLimitUSD: Double
    var softAlertThreshold: Double   // 0.0–1.0, e.g. 0.8 = 80%
    var currentSpendUSD: Double
    var tokenUsage: TokenUsage
    var autoPauseEnabled: Bool

    init(
        monthlyLimitUSD: Double = 50,
        softAlertThreshold: Double = 0.8,
        currentSpendUSD: Double = 0,
        tokenUsage: TokenUsage = TokenUsage(),
        autoPauseEnabled: Bool = false
    ) {
        self.monthlyLimitUSD = monthlyLimitUSD
        self.softAlertThreshold = softAlertThreshold
        self.currentSpendUSD = currentSpendUSD
        self.tokenUsage = tokenUsage
        self.autoPauseEnabled = autoPauseEnabled
    }
}

struct TokenUsage: Codable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalCostUSD: Double
    var lastUpdated: Date

    init(inputTokens: Int = 0, outputTokens: Int = 0, totalCostUSD: Double = 0, lastUpdated: Date = Date()) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalCostUSD = totalCostUSD
        self.lastUpdated = lastUpdated
    }
}

struct CostEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var agentName: String
    var projectId: String?
    var issueId: String?
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var model: String
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        agentName: String,
        projectId: String? = nil,
        issueId: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        model: String,
        timestamp: Date = Date()
    ) {
        self.id = id; self.agentName = agentName
        self.projectId = projectId; self.issueId = issueId
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.costUSD = costUSD; self.model = model; self.timestamp = timestamp
    }
}

// Budget status for UI coloring
enum BudgetStatus: Sendable {
    case ok        // below softAlertThreshold
    case warning   // above softAlertThreshold, below limit
    case exceeded  // above monthlyLimit
    case noLimit   // no budget config set
}

// MARK: - Governance & Approval Models

enum ApprovalType: String, Codable, CaseIterable, Sendable {
    case agentHire       = "agent_hire"
    case budgetChange    = "budget_change"
    case strategyChange  = "strategy_change"
    case highRiskAction  = "high_risk_action"
    case projectCreation = "project_creation"
    case deployment      = "deployment"

    var label: String {
        switch self {
        case .agentHire:       return "Agent Hire"
        case .budgetChange:    return "Budget Change"
        case .strategyChange:  return "Strategy Change"
        case .highRiskAction:  return "High-Risk Action"
        case .projectCreation: return "Project Creation"
        case .deployment:      return "Deployment"
        }
    }

    var icon: String {
        switch self {
        case .agentHire:       return "person.badge.plus"
        case .budgetChange:    return "dollarsign.circle"
        case .strategyChange:  return "arrow.triangle.branch"
        case .highRiskAction:  return "exclamationmark.triangle"
        case .projectCreation: return "folder.badge.plus"
        case .deployment:      return "arrow.up.circle"
        }
    }
}

enum ApprovalStatus: String, Codable, CaseIterable, Sendable {
    case pending            = "pending"
    case approved           = "approved"
    case rejected           = "rejected"
    case revisionRequested  = "revision_requested"

    var label: String {
        switch self {
        case .pending:           return "Pending"
        case .approved:          return "Approved"
        case .rejected:          return "Rejected"
        case .revisionRequested: return "Revision Requested"
        }
    }

    var icon: String {
        switch self {
        case .pending:           return "clock"
        case .approved:          return "checkmark.circle.fill"
        case .rejected:          return "xmark.circle.fill"
        case .revisionRequested: return "arrow.clockwise.circle.fill"
        }
    }
}

enum ApprovalAction: String, Codable, Sendable {
    case approve         = "approve"
    case reject          = "reject"
    case requestRevision = "request_revision"
}

struct ApprovalDecision: Codable, Hashable, Sendable {
    var decidedBy: String
    var action: ApprovalAction
    var notes: String?
    var decidedAt: Date

    init(decidedBy: String = "board", action: ApprovalAction, notes: String? = nil, decidedAt: Date = Date()) {
        self.decidedBy = decidedBy; self.action = action
        self.notes = notes; self.decidedAt = decidedAt
    }
}

struct ApprovalRequest: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var type: ApprovalType
    var title: String
    var description: String
    var requestedBy: String
    var status: ApprovalStatus
    var decision: ApprovalDecision?
    var metadata: [String: String]
    var createdAt: Date
    var decidedAt: Date?

    init(
        id: String = UUID().uuidString,
        type: ApprovalType,
        title: String,
        description: String = "",
        requestedBy: String,
        status: ApprovalStatus = .pending,
        decision: ApprovalDecision? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        decidedAt: Date? = nil
    ) {
        self.id = id; self.type = type; self.title = title
        self.description = description; self.requestedBy = requestedBy
        self.status = status; self.decision = decision
        self.metadata = metadata; self.createdAt = createdAt; self.decidedAt = decidedAt
    }
}

// Which approval types are required (stored in config.json)
struct GovernanceConfig: Codable, Sendable {
    var requiredApprovalTypes: Set<String>

    init(requiredApprovalTypes: Set<String> = Set(ApprovalType.allCases.map { $0.rawValue })) {
        self.requiredApprovalTypes = requiredApprovalTypes
    }
}

// MARK: - Activity Feed Models

enum ActivityCategory: String, CaseIterable, Sendable {
    case all       = "All"
    case issues    = "Issues"
    case agents    = "Agents"
    case approvals = "Approvals"
    case costs     = "Costs"
    case routines  = "Routines"
    case org       = "Org"
    case tasks     = "Tasks"
}

enum ActivityType: String, Codable, CaseIterable, Sendable {
    // Issues
    case issueCreated   = "issue_created"
    case issueUpdated   = "issue_updated"
    case issueCompleted = "issue_completed"
    // Tasks (legacy)
    case taskCreated    = "task_created"
    case taskCompleted  = "task_completed"
    case taskFailed     = "task_failed"
    // Agents
    case agentSpawned   = "agent_spawned"
    case agentCompleted = "agent_completed"
    case agentPaused    = "agent_paused"
    // Approvals
    case approvalRequested = "approval_requested"
    case approvalDecided   = "approval_decided"
    // Costs
    case costLogged    = "cost_logged"
    case budgetAlert   = "budget_alert"
    // Routines
    case routineFired  = "routine_fired"
    case routineAdded  = "routine_added"
    // Org
    case orgNodeAdded   = "org_node_added"
    case orgNodeUpdated = "org_node_updated"
    case orgNodeRemoved = "org_node_removed"
    // General
    case custom = "custom"

    var label: String {
        switch self {
        case .issueCreated:      return "Issue Created"
        case .issueUpdated:      return "Issue Updated"
        case .issueCompleted:    return "Issue Completed"
        case .taskCreated:       return "Task Created"
        case .taskCompleted:     return "Task Completed"
        case .taskFailed:        return "Task Failed"
        case .agentSpawned:      return "Agent Spawned"
        case .agentCompleted:    return "Agent Completed"
        case .agentPaused:       return "Agent Paused"
        case .approvalRequested: return "Approval Requested"
        case .approvalDecided:   return "Approval Decided"
        case .costLogged:        return "Cost Logged"
        case .budgetAlert:       return "Budget Alert"
        case .routineFired:      return "Routine Fired"
        case .routineAdded:      return "Routine Added"
        case .orgNodeAdded:      return "Org Node Added"
        case .orgNodeUpdated:    return "Org Node Updated"
        case .orgNodeRemoved:    return "Org Node Removed"
        case .custom:            return "Event"
        }
    }

    var icon: String {
        switch self {
        case .issueCreated, .issueUpdated: return "doc.badge.plus"
        case .issueCompleted:              return "checkmark.circle.fill"
        case .taskCreated:                 return "plus.circle"
        case .taskCompleted:               return "checkmark.circle.fill"
        case .taskFailed:                  return "xmark.circle.fill"
        case .agentSpawned:                return "bolt.fill"
        case .agentCompleted:              return "flag.checkered"
        case .agentPaused:                 return "pause.fill"
        case .approvalRequested:           return "clock.badge.exclamationmark"
        case .approvalDecided:             return "checkmark.shield.fill"
        case .costLogged:                  return "dollarsign.circle"
        case .budgetAlert:                 return "exclamationmark.triangle.fill"
        case .routineFired:                return "clock.arrow.2.circlepath"
        case .routineAdded:                return "plus.circle.fill"
        case .orgNodeAdded:                return "person.badge.plus"
        case .orgNodeUpdated:              return "person.fill.viewfinder"
        case .orgNodeRemoved:              return "person.fill.xmark"
        case .custom:                      return "star.fill"
        }
    }

    var category: ActivityCategory {
        switch self {
        case .issueCreated, .issueUpdated, .issueCompleted:    return .issues
        case .taskCreated, .taskCompleted, .taskFailed:        return .tasks
        case .agentSpawned, .agentCompleted, .agentPaused:     return .agents
        case .approvalRequested, .approvalDecided:             return .approvals
        case .costLogged, .budgetAlert:                        return .costs
        case .routineFired, .routineAdded:                     return .routines
        case .orgNodeAdded, .orgNodeUpdated, .orgNodeRemoved:  return .org
        case .custom:                                          return .tasks
        }
    }
}

struct ActivityEntry: Codable, Identifiable, Sendable {
    let id: String
    var type: ActivityType
    var actor: String
    var summary: String
    var metadata: [String: String]
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        type: ActivityType,
        actor: String,
        summary: String,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.id = id; self.type = type; self.actor = actor
        self.summary = summary; self.metadata = metadata; self.timestamp = timestamp
    }
}

// MARK: - Routines Models

enum ScheduleType: String, Codable, CaseIterable, Sendable {
    case interval = "interval"
    case daily    = "daily"
    case weekly   = "weekly"
    case monthly  = "monthly"

    var label: String {
        switch self {
        case .interval: return "Interval"
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        }
    }

    var icon: String {
        switch self {
        case .interval: return "timer"
        case .daily:    return "sun.max"
        case .weekly:   return "calendar.badge.clock"
        case .monthly:  return "calendar"
        }
    }
}

struct RoutineSchedule: Codable, Hashable, Sendable {
    var type: ScheduleType
    var intervalMinutes: Int?   // for .interval — how many minutes between runs
    var timeOfDay: String?      // "HH:MM" for .daily / .weekly / .monthly
    var weekday: Int?           // 0=Sun … 6=Sat for .weekly
    var dayOfMonth: Int?        // 1–28 for .monthly

    init(
        type: ScheduleType = .daily,
        intervalMinutes: Int? = 60,
        timeOfDay: String? = "09:00",
        weekday: Int? = 1,
        dayOfMonth: Int? = 1
    ) {
        self.type = type; self.intervalMinutes = intervalMinutes
        self.timeOfDay = timeOfDay; self.weekday = weekday
        self.dayOfMonth = dayOfMonth
    }

    /// Human-readable one-liner
    var summary: String {
        switch type {
        case .interval:
            let mins = intervalMinutes ?? 60
            if mins < 60  { return "Every \(mins) minutes" }
            if mins == 60 { return "Every hour" }
            let h = mins / 60; let m = mins % 60
            return m == 0 ? "Every \(h)h" : "Every \(h)h \(m)m"
        case .daily:
            return "Daily at \(timeOfDay ?? "09:00")"
        case .weekly:
            let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            let d = days[min(weekday ?? 1, 6)]
            return "\(d) at \(timeOfDay ?? "09:00")"
        case .monthly:
            return "Day \(dayOfMonth ?? 1) of month at \(timeOfDay ?? "09:00")"
        }
    }
}

struct IssueTemplate: Codable, Hashable, Sendable {
    var title: String
    var description: String
    var priority: IssuePriority
    var labels: [String]
    var projectId: String?
    var milestoneId: String?

    init(
        title: String = "",
        description: String = "",
        priority: IssuePriority = .normal,
        labels: [String] = [],
        projectId: String? = nil,
        milestoneId: String? = nil
    ) {
        self.title = title; self.description = description
        self.priority = priority; self.labels = labels
        self.projectId = projectId; self.milestoneId = milestoneId
    }
}

struct Routine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String
    var assignee: String?
    var schedule: RoutineSchedule
    var issueTemplate: IssueTemplate
    var enabled: Bool
    var lastRun: Date?
    var nextRun: Date?
    var runCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        assignee: String? = nil,
        schedule: RoutineSchedule = RoutineSchedule(),
        issueTemplate: IssueTemplate = IssueTemplate(),
        enabled: Bool = true,
        lastRun: Date? = nil,
        nextRun: Date? = nil,
        runCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.description = description
        self.assignee = assignee; self.schedule = schedule
        self.issueTemplate = issueTemplate; self.enabled = enabled
        self.lastRun = lastRun; self.nextRun = nextRun
        self.runCount = runCount; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct RoutineLog: Codable, Identifiable, Sendable {
    let id: String
    var routineId: String
    var routineTitle: String
    var issueId: String?
    var issueTitle: String?
    var firedAt: Date
    var success: Bool
    var error: String?

    init(
        id: String = UUID().uuidString,
        routineId: String,
        routineTitle: String,
        issueId: String? = nil,
        issueTitle: String? = nil,
        firedAt: Date = Date(),
        success: Bool = true,
        error: String? = nil
    ) {
        self.id = id; self.routineId = routineId; self.routineTitle = routineTitle
        self.issueId = issueId; self.issueTitle = issueTitle
        self.firedAt = firedAt; self.success = success; self.error = error
    }
}

// MARK: - Org Chart Models

enum OrgRole: String, Codable, CaseIterable, Sendable {
    case ceo        = "ceo"
    case teamLead   = "team_lead"
    case engineer   = "engineer"
    case specialist = "specialist"

    var label: String {
        switch self {
        case .ceo:        return "CEO"
        case .teamLead:   return "Team Lead"
        case .engineer:   return "Engineer"
        case .specialist: return "Specialist"
        }
    }

    var icon: String {
        switch self {
        case .ceo:        return "crown"
        case .teamLead:   return "person.2"
        case .engineer:   return "hammer"
        case .specialist: return "sparkles"
        }
    }

    /// Sort priority (lower = higher in hierarchy)
    var priority: Int {
        switch self {
        case .ceo: return 0; case .teamLead: return 1
        case .engineer: return 2; case .specialist: return 3
        }
    }
}

enum AgentOrgStatus: String, Codable, CaseIterable, Sendable {
    case active  = "active"
    case idle    = "idle"
    case paused  = "paused"
    case offline = "offline"

    var label: String {
        switch self {
        case .active:  return "Active"
        case .idle:    return "Idle"
        case .paused:  return "Paused"
        case .offline: return "Offline"
        }
    }
}

struct OrgNode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var agentName: String
    var role: OrgRole
    var title: String
    var reportsTo: String?
    var team: String?
    var responsibilities: [String]
    var skills: [String]
    var status: AgentOrgStatus
    var currentTask: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        agentName: String,
        role: OrgRole = .engineer,
        title: String = "",
        reportsTo: String? = nil,
        team: String? = nil,
        responsibilities: [String] = [],
        skills: [String] = [],
        status: AgentOrgStatus = .idle,
        currentTask: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.agentName = agentName; self.role = role
        self.title = title; self.reportsTo = reportsTo; self.team = team
        self.responsibilities = responsibilities; self.skills = skills
        self.status = status; self.currentTask = currentTask
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    var avatarInitials: String {
        let words = agentName.components(separatedBy: CharacterSet.whitespacesAndNewlines
            .union(.init(charactersIn: "-_")))
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(agentName.prefix(2)).uppercased()
    }
}

// MARK: - Import / Export Models

struct MasterConfigExport: Codable, Sendable {
    var version: String          = "1.0"
    var exportDate: Date
    var appVersion: String       = "1.0.0"
    var sections: ExportSections
}

struct ExportSections: Codable, Sendable {
    var goals:            [Goal]?
    var projects:         [Project]?
    var milestones:       [Milestone]?
    var issues:           [Issue]?
    var orgNodes:         [OrgNode]?
    var budgets:          [String: BudgetConfig]?
    var routines:         [Routine]?
    var governanceConfig: GovernanceConfig?
    var pendingApprovals: [ApprovalRequest]?
    var skills:           [SkillExport]?
    var agents:           [AgentExport]?
    var mcpServers:       [McpServer]?
}

struct SkillExport: Codable, Sendable {
    var name: String
    var content: String
}

struct AgentExport: Codable, Sendable {
    var name: String
    var content: String
    var isGlobal: Bool
}

// MARK: - Import Preview

struct ImportPreview: Sendable {
    var version: String
    var exportDate: Date
    var appVersion: String
    var goalCount: Int         = 0
    var projectCount: Int      = 0
    var milestoneCount: Int    = 0
    var issueCount: Int        = 0
    var orgNodeCount: Int      = 0
    var budgetCount: Int       = 0
    var routineCount: Int      = 0
    var skillCount: Int        = 0
    var agentCount: Int        = 0
    var mcpServerCount: Int    = 0
    var approvalCount: Int     = 0
    var conflicts: [ImportConflict] = []

    var totalCount: Int {
        goalCount + projectCount + milestoneCount + issueCount + orgNodeCount +
        budgetCount + routineCount + skillCount + agentCount + mcpServerCount + approvalCount
    }
}

struct ImportConflict: Identifiable, Sendable {
    let id: String
    var section: String
    var itemName: String
    var resolution: ConflictResolution = .skip
}

enum ConflictResolution: String, CaseIterable, Sendable {
    case skip, overwrite, rename
    var label: String {
        switch self {
        case .skip:      return "Skip"
        case .overwrite: return "Overwrite"
        case .rename:    return "Auto-rename"
        }
    }
}

struct ExportSectionItem: Identifiable, Sendable {
    let id: String
    var label: String
    var icon: String
    var count: Int
    var isSelected: Bool
}
