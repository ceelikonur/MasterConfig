import Foundation
import Observation

// MARK: - Fleet Service

@MainActor
@Observable
final class FleetService {

    private(set) var projects: [FleetProject] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private let fm = FileManager.default

    init() {}

    // MARK: - Paths

    private var storeURL: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("MasterConfig", isDirectory: true)
            .appendingPathComponent("fleet.json", isDirectory: false)
    }

    // MARK: - Load / Save

    func load() {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let url = storeURL
        guard fm.fileExists(atPath: url.path) else {
            projects = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder.iso.decode(FleetStore.self, from: data)
            projects = store.projects
        } catch {
            lastError = "Failed to load fleet: \(error.localizedDescription)"
            projects = []
        }
    }

    private func save() {
        let url = storeURL
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let store = FleetStore(projects: projects)
            let data = try JSONEncoder.iso.encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            lastError = "Failed to save fleet: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func addProject(_ project: FleetProject) {
        projects.append(project)
        save()
    }

    func updateProject(_ project: FleetProject) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        updated.updatedAt = Date()
        projects[idx] = updated
        save()
    }

    func removeProject(id: String) {
        projects.removeAll { $0.id == id }
        save()
    }

    func project(id: String) -> FleetProject? {
        projects.first { $0.id == id }
    }

    // MARK: - Health Refresh

    func refreshHealth(for projectID: String) async {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = projects[idx]

        // Short-circuit: no integrations configured.
        if project.github == nil && project.supabase == nil && project.netlify == nil {
            projects[idx].lastCheckedAt = Date()
            projects[idx].updatedAt = Date()
            save()
            return
        }

        var issues: [FleetIssue] = []

        // Resolve tokens up front (off the main actor for keychain).
        let githubToken: String? = await tokenOrIssue(for: project.github?.tokenKeychainKey,
                                                      source: .github,
                                                      into: &issues)
        let supabaseToken: String? = await tokenOrIssue(for: project.supabase?.tokenKeychainKey,
                                                        source: .supabase,
                                                        into: &issues)
        let netlifyToken: String? = await tokenOrIssue(for: project.netlify?.tokenKeychainKey,
                                                       source: .netlify,
                                                       into: &issues)

        // Build clients lazily.
        let ghRef = project.github
        let sbRef = project.supabase
        let nfRef = project.netlify

        async let ghFetch: GitHubFetchResult? = {
            guard let ref = ghRef, let token = githubToken else { return nil }
            let client = GitHubClient(config: .init(owner: ref.owner, repo: ref.repo, token: token))
            return await client.fetchHealth(defaultBranch: ref.defaultBranch)
        }()

        async let sbFetch: SupabaseFetchResult? = {
            guard let ref = sbRef, let token = supabaseToken else { return nil }
            let client = SupabaseManagementClient(config: .init(projectRef: ref.projectRef, token: token))
            return await client.fetchHealth()
        }()

        async let nfFetch: NetlifyFetchResult? = {
            guard let ref = nfRef, let token = netlifyToken else { return nil }
            let client = NetlifyClient(config: .init(siteId: ref.siteId, token: token))
            return await client.fetchHealth()
        }()

        let ghResult = await ghFetch
        let sbResult = await sbFetch
        let nfResult = await nfFetch

        if let r = ghResult { issues.append(contentsOf: r.issues) }
        if let r = sbResult { issues.append(contentsOf: r.issues) }
        if let r = nfResult { issues.append(contentsOf: r.issues) }

        // Determine if any integration produced data at all.
        let configured = (ghRef != nil) || (sbRef != nil) || (nfRef != nil)
        let anyFetched =
            (ghRef != nil && ghResult != nil) ||
            (sbRef != nil && sbResult != nil) ||
            (nfRef != nil && nfResult != nil)

        let (score, status) = computeScore(
            configured: configured,
            anyFetched: anyFetched,
            github: ghResult?.health,
            supabase: sbResult?.health,
            netlify: nfResult?.health,
            issues: issues
        )

        let snapshot = FleetHealth(
            score: score,
            status: status,
            github: ghResult?.health,
            supabase: sbResult?.health,
            netlify: nfResult?.health,
            issues: issues,
            fetchedAt: Date()
        )

        projects[idx].lastHealth = snapshot
        projects[idx].lastCheckedAt = Date()
        projects[idx].updatedAt = Date()
        save()
    }

    func refreshAllHealth() async {
        // Bounded concurrency (~3) to avoid rate-limit bursts.
        let maxConcurrent = 3
        let ids = projects.map(\.id)
        var index = 0

        await withTaskGroup(of: Void.self) { group in
            // Prime up to maxConcurrent tasks.
            while index < ids.count && index < maxConcurrent {
                let pid = ids[index]
                group.addTask { [weak self] in
                    await self?.refreshHealth(for: pid)
                }
                index += 1
            }
            // As each finishes, kick off the next.
            while await group.next() != nil {
                if index < ids.count {
                    let pid = ids[index]
                    group.addTask { [weak self] in
                        await self?.refreshHealth(for: pid)
                    }
                    index += 1
                }
            }
        }
    }

    // MARK: - Helpers

    private func tokenOrIssue(
        for key: String?,
        source: FleetIssueSource,
        into issues: inout [FleetIssue]
    ) async -> String? {
        guard let key, !key.isEmpty else { return nil }
        do {
            if let token = try await KeychainService.shared.getToken(forKey: key), !token.isEmpty {
                return token
            }
            issues.append(
                FleetIssue(
                    severity: .critical,
                    source: source,
                    message: "Missing keychain token for key '\(key)'"
                )
            )
            return nil
        } catch {
            issues.append(
                FleetIssue(
                    severity: .critical,
                    source: source,
                    message: "Keychain error for key '\(key)': \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    // MARK: - Scoring
    //
    // Rubric (tune over time):
    // - Base score: 100.
    // - GitHub:  -15 if lastWorkflowConclusion == "failure"
    //            -5 per openPR over 5 (capped at -25)
    //            -10 if no commit in the last 14 days
    // - Supabase: -30 per RLS-disabled table (cap at -60)
    //             -20 if projectStatus != "ACTIVE_HEALTHY"
    // - Netlify:  -40 if lastDeployState == "error"
    //             -10 if > 30 days since last deploy
    // - Each critical issue subtracts another -20.
    // - Clamp to 0...100.
    // - Status:
    //     >= 85  → .healthy
    //     >= 60  → .warning
    //     <  60  → .critical
    //     No integration returned health data → .unknown

    private func computeScore(
        configured: Bool,
        anyFetched: Bool,
        github: GitHubHealth?,
        supabase: SupabaseHealth?,
        netlify: NetlifyHealth?,
        issues: [FleetIssue]
    ) -> (Int, FleetHealthStatus) {
        guard configured else {
            return (100, .healthy)
        }
        guard anyFetched else {
            return (0, .unknown)
        }

        var score = 100
        let now = Date()

        if let gh = github {
            if gh.lastWorkflowConclusion == "failure" {
                score -= 15
            }
            if gh.openPRCount > 5 {
                score -= min(25, (gh.openPRCount - 5) * 5)
            }
            if let commitAt = gh.lastCommitAt {
                let days = now.timeIntervalSince(commitAt) / 86_400
                if days > 14 {
                    score -= 10
                }
            }
        }

        if let sb = supabase {
            if !sb.rlsDisabledTables.isEmpty {
                score -= min(60, sb.rlsDisabledTables.count * 30)
            }
            if let status = sb.projectStatus, status != "ACTIVE_HEALTHY" {
                score -= 20
            }
        }

        if let nf = netlify {
            if nf.lastDeployState == "error" {
                score -= 40
            }
            if let deployAt = nf.lastDeployAt {
                let days = now.timeIntervalSince(deployAt) / 86_400
                if days > 30 {
                    score -= 10
                }
            }
        }

        let criticalCount = issues.filter { $0.severity == .critical }.count
        score -= criticalCount * 20

        let clamped = max(0, min(100, score))
        let status: FleetHealthStatus
        if clamped >= 85        { status = .healthy }
        else if clamped >= 60   { status = .warning }
        else                    { status = .critical }
        return (clamped, status)
    }
}
