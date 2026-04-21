import Foundation

// MARK: - Fleet: Top-level Project

struct FleetProject: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var clientName: String?
    var notes: String?

    var github: GitHubRef?
    var supabase: SupabaseRef?
    var netlify: NetlifyRef?

    var lastHealth: FleetHealth?
    var lastCheckedAt: Date?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        clientName: String? = nil,
        notes: String? = nil,
        github: GitHubRef? = nil,
        supabase: SupabaseRef? = nil,
        netlify: NetlifyRef? = nil,
        lastHealth: FleetHealth? = nil,
        lastCheckedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.clientName = clientName; self.notes = notes
        self.github = github; self.supabase = supabase; self.netlify = netlify
        self.lastHealth = lastHealth; self.lastCheckedAt = lastCheckedAt
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// MARK: - Fleet: Integration Refs

struct GitHubRef: Codable, Hashable, Sendable {
    var owner: String
    var repo: String
    var defaultBranch: String?
    var tokenKeychainKey: String

    init(owner: String, repo: String, defaultBranch: String? = nil, tokenKeychainKey: String) {
        self.owner = owner; self.repo = repo
        self.defaultBranch = defaultBranch; self.tokenKeychainKey = tokenKeychainKey
    }
}

struct SupabaseRef: Codable, Hashable, Sendable {
    var projectRef: String
    var region: String?
    var tokenKeychainKey: String

    init(projectRef: String, region: String? = nil, tokenKeychainKey: String) {
        self.projectRef = projectRef; self.region = region
        self.tokenKeychainKey = tokenKeychainKey
    }
}

struct NetlifyRef: Codable, Hashable, Sendable {
    var siteId: String
    var siteName: String?
    var tokenKeychainKey: String

    init(siteId: String, siteName: String? = nil, tokenKeychainKey: String) {
        self.siteId = siteId; self.siteName = siteName
        self.tokenKeychainKey = tokenKeychainKey
    }
}

// MARK: - Fleet: Health Snapshot

struct FleetHealth: Codable, Hashable, Sendable {
    var score: Int
    var status: FleetHealthStatus
    var github: GitHubHealth?
    var supabase: SupabaseHealth?
    var netlify: NetlifyHealth?
    var issues: [FleetIssue]
    var fetchedAt: Date

    init(
        score: Int = 0,
        status: FleetHealthStatus = .unknown,
        github: GitHubHealth? = nil,
        supabase: SupabaseHealth? = nil,
        netlify: NetlifyHealth? = nil,
        issues: [FleetIssue] = [],
        fetchedAt: Date = Date()
    ) {
        self.score = score; self.status = status
        self.github = github; self.supabase = supabase; self.netlify = netlify
        self.issues = issues; self.fetchedAt = fetchedAt
    }
}

enum FleetHealthStatus: String, Codable, Sendable, CaseIterable {
    case healthy, warning, critical, unknown

    var label: String {
        switch self {
        case .healthy:  return "Healthy"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        case .unknown:  return "Unknown"
        }
    }

    var color: String {
        switch self {
        case .healthy:  return "green"
        case .warning:  return "yellow"
        case .critical: return "red"
        case .unknown:  return "gray"
        }
    }

    var icon: String {
        switch self {
        case .healthy:  return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown:  return "questionmark.circle"
        }
    }
}

// MARK: - Fleet: Per-Integration Health

struct GitHubHealth: Codable, Hashable, Sendable {
    var defaultBranch: String
    var lastCommitSHA: String?
    var lastCommitMessage: String?
    var lastCommitAuthor: String?
    var lastCommitAt: Date?
    var openPRCount: Int
    var lastWorkflowConclusion: String?
    var lastWorkflowRunAt: Date?

    init(
        defaultBranch: String,
        lastCommitSHA: String? = nil,
        lastCommitMessage: String? = nil,
        lastCommitAuthor: String? = nil,
        lastCommitAt: Date? = nil,
        openPRCount: Int = 0,
        lastWorkflowConclusion: String? = nil,
        lastWorkflowRunAt: Date? = nil
    ) {
        self.defaultBranch = defaultBranch
        self.lastCommitSHA = lastCommitSHA
        self.lastCommitMessage = lastCommitMessage
        self.lastCommitAuthor = lastCommitAuthor
        self.lastCommitAt = lastCommitAt
        self.openPRCount = openPRCount
        self.lastWorkflowConclusion = lastWorkflowConclusion
        self.lastWorkflowRunAt = lastWorkflowRunAt
    }
}

struct SupabaseHealth: Codable, Hashable, Sendable {
    var projectStatus: String?
    var tableCount: Int?
    var rlsDisabledTables: [String]
    var lastCheckedAt: Date

    init(
        projectStatus: String? = nil,
        tableCount: Int? = nil,
        rlsDisabledTables: [String] = [],
        lastCheckedAt: Date = Date()
    ) {
        self.projectStatus = projectStatus
        self.tableCount = tableCount
        self.rlsDisabledTables = rlsDisabledTables
        self.lastCheckedAt = lastCheckedAt
    }
}

struct NetlifyHealth: Codable, Hashable, Sendable {
    var lastDeployState: String?
    var lastDeployBranch: String?
    var lastDeployAt: Date?
    var lastDeployURL: String?
    var lastDeployErrorMessage: String?

    init(
        lastDeployState: String? = nil,
        lastDeployBranch: String? = nil,
        lastDeployAt: Date? = nil,
        lastDeployURL: String? = nil,
        lastDeployErrorMessage: String? = nil
    ) {
        self.lastDeployState = lastDeployState
        self.lastDeployBranch = lastDeployBranch
        self.lastDeployAt = lastDeployAt
        self.lastDeployURL = lastDeployURL
        self.lastDeployErrorMessage = lastDeployErrorMessage
    }
}

// MARK: - Fleet: Issues

struct FleetIssue: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var severity: FleetIssueSeverity
    var source: FleetIssueSource
    var message: String
    var detectedAt: Date

    init(
        id: String = UUID().uuidString,
        severity: FleetIssueSeverity,
        source: FleetIssueSource,
        message: String,
        detectedAt: Date = Date()
    ) {
        self.id = id; self.severity = severity; self.source = source
        self.message = message; self.detectedAt = detectedAt
    }
}

enum FleetIssueSeverity: String, Codable, Sendable, CaseIterable {
    case info, warning, critical

    var label: String {
        switch self {
        case .info:     return "Info"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }

    var icon: String {
        switch self {
        case .info:     return "info.circle"
        case .warning:  return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    var color: String {
        switch self {
        case .info:     return "blue"
        case .warning:  return "yellow"
        case .critical: return "red"
        }
    }
}

enum FleetIssueSource: String, Codable, Sendable, CaseIterable {
    case github, supabase, netlify, fleet

    var label: String {
        switch self {
        case .github:   return "GitHub"
        case .supabase: return "Supabase"
        case .netlify:  return "Netlify"
        case .fleet:    return "Fleet"
        }
    }

    var icon: String {
        switch self {
        case .github:   return "chevron.left.forwardslash.chevron.right"
        case .supabase: return "cylinder.split.1x2"
        case .netlify:  return "globe"
        case .fleet:    return "shippingbox"
        }
    }
}

// MARK: - Fleet: Persistent Store

struct FleetStore: Codable, Sendable {
    var projects: [FleetProject]

    init(projects: [FleetProject] = []) {
        self.projects = projects
    }
}
