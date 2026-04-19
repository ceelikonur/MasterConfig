import Foundation

// MARK: - JSON Codec Helpers

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

// MARK: - Hierarchy Service

@Observable
@MainActor
final class HierarchyService {

    // Published state
    var goals: [Goal]       = []
    var projects: [Project] = []
    var milestones: [Milestone] = []
    var issues: [Issue]     = []
    var isLoading           = false

    private let fm = FileManager.default

    // MARK: - Paths

    private var baseDir: String    { NSHomeDirectory() + "/.claude/orchestrator" }
    private var hierarchyFile: String { baseDir + "/hierarchy.json" }
    private var projectsDir: String   { baseDir + "/projects" }
    private var issuesDir: String     { baseDir + "/issues" }

    // MARK: - Bootstrap

    func load() {
        isLoading = true
        defer { isLoading = false }
        ensureDirs()
        loadHierarchy()
        loadProjects()
        loadIssues()
    }

    private func ensureDirs() {
        [baseDir, projectsDir, issuesDir].forEach {
            try? fm.createDirectory(atPath: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: - Loaders

    private func loadHierarchy() {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: hierarchyFile)),
            let h    = try? JSONDecoder.iso.decode(TaskHierarchy.self, from: data)
        else {
            goals = []; milestones = []
            return
        }
        goals      = h.goals
        milestones = h.milestones
    }

    private func loadProjects() {
        let url = URL(fileURLWithPath: projectsDir)
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            projects = []; return
        }
        projects = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder.iso.decode(Project.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func loadIssues() {
        let url = URL(fileURLWithPath: issuesDir)
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            issues = []; return
        }
        issues = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder.iso.decode(Issue.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Atomic Write

    private func atomicWrite(_ data: Data, to path: String) {
        let tmpPath = path + ".tmp"
        let tmpURL  = URL(fileURLWithPath: tmpPath)
        let destURL = URL(fileURLWithPath: path)
        do {
            try data.write(to: tmpURL, options: .atomic)
            if fm.fileExists(atPath: path) {
                _ = try fm.replaceItemAt(destURL, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: destURL)
            }
        } catch {
            try? data.write(to: destURL)   // last-resort direct write
        }
    }

    private func saveHierarchy() {
        guard let data = try? JSONEncoder.iso.encode(TaskHierarchy(goals: goals, milestones: milestones))
        else { return }
        atomicWrite(data, to: hierarchyFile)
    }

    private func saveProject(_ p: Project) {
        guard let data = try? JSONEncoder.iso.encode(p) else { return }
        atomicWrite(data, to: projectsDir + "/\(p.id).json")
    }

    private func saveIssue(_ i: Issue) {
        guard let data = try? JSONEncoder.iso.encode(i) else { return }
        atomicWrite(data, to: issuesDir + "/\(i.id).json")
    }

    // MARK: - CRUD: Goals

    @discardableResult
    func createGoal(title: String, description: String = "") -> Goal {
        let g = Goal(title: title, description: description)
        goals.append(g)
        saveHierarchy()
        return g
    }

    func updateGoal(_ id: String, title: String? = nil, status: GoalStatus? = nil) {
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return }
        if let v = title  { goals[idx].title = v }
        if let v = status { goals[idx].status = v }
        goals[idx].updatedAt = Date()
        saveHierarchy()
    }

    // MARK: - CRUD: Projects

    @discardableResult
    func createProject(title: String, description: String = "", goalId: String? = nil) -> Project {
        let p = Project(title: title, description: description, goalId: goalId)
        if let gid = goalId, let idx = goals.firstIndex(where: { $0.id == gid }) {
            goals[idx].projectIds.append(p.id)
            goals[idx].updatedAt = Date()
            saveHierarchy()
        }
        projects.append(p)
        saveProject(p)
        return p
    }

    // MARK: - CRUD: Milestones

    @discardableResult
    func createMilestone(title: String, projectId: String, dueDate: Date? = nil) -> Milestone {
        let m = Milestone(title: title, projectId: projectId, dueDate: dueDate)
        milestones.append(m)
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[idx].milestoneIds.append(m.id)
            saveProject(projects[idx])
        }
        saveHierarchy()
        return m
    }

    // MARK: - CRUD: Issues

    @discardableResult
    func createIssue(
        title: String,
        description: String = "",
        projectId: String? = nil,
        milestoneId: String? = nil,
        parentIssueId: String? = nil,
        assignee: String? = nil,
        priority: IssuePriority = .normal,
        labels: [String] = []
    ) -> Issue {
        let issue = Issue(
            title: title, description: description,
            milestoneId: milestoneId, projectId: projectId,
            parentIssueId: parentIssueId, assignee: assignee,
            priority: priority, labels: labels
        )
        issues.append(issue)
        if let mid = milestoneId, let idx = milestones.firstIndex(where: { $0.id == mid }) {
            milestones[idx].issueIds.append(issue.id)
            saveHierarchy()
        }
        saveIssue(issue)
        return issue
    }

    func updateIssue(
        _ id: String,
        title: String? = nil,
        description: String? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        assignee: String? = nil,
        labels: [String]? = nil
    ) {
        guard let idx = issues.firstIndex(where: { $0.id == id }) else { return }
        if let v = title       { issues[idx].title = v }
        if let v = description { issues[idx].description = v }
        if let v = status      { issues[idx].status = v }
        if let v = priority    { issues[idx].priority = v }
        if let v = assignee    { issues[idx].assignee = v }
        if let v = labels      { issues[idx].labels = v }
        issues[idx].updatedAt = Date()
        saveIssue(issues[idx])
    }

    func addComment(to issueId: String, author: String, body: String) {
        guard let idx = issues.firstIndex(where: { $0.id == issueId }) else { return }
        issues[idx].comments.append(IssueComment(author: author, body: body))
        issues[idx].updatedAt = Date()
        saveIssue(issues[idx])
    }

    func deleteIssue(_ id: String) {
        guard let idx = issues.firstIndex(where: { $0.id == id }) else { return }
        let issue = issues.remove(at: idx)
        if let mid = issue.milestoneId, let midx = milestones.firstIndex(where: { $0.id == mid }) {
            milestones[midx].issueIds.removeAll { $0 == id }
            saveHierarchy()
        }
        try? fm.removeItem(atPath: issuesDir + "/\(id).json")
    }

    // MARK: - Query Helpers

    func projects(for goalId: String) -> [Project] {
        projects.filter { $0.goalId == goalId }
    }

    func milestones(for projectId: String) -> [Milestone] {
        milestones.filter { $0.projectId == projectId }
    }

    func issues(for context: IssueContext) -> [Issue] {
        switch context {
        case .all:
            return issues
        case .milestone(let id):
            return issues.filter { $0.milestoneId == id }
        case .project(let id):
            return issues.filter { $0.projectId == id }
        case .goal(let id):
            let pids = Set(projects(for: id).map { $0.id })
            return issues.filter { $0.projectId.map { pids.contains($0) } ?? false }
        }
    }
}
