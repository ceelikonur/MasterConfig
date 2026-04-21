import Foundation

// MARK: - Result

struct GitHubFetchResult: Sendable {
    var health: GitHubHealth
    var issues: [FleetIssue]
}

// MARK: - GitHub Client

actor GitHubClient {

    struct Config: Sendable {
        let owner: String
        let repo: String
        let token: String
    }

    enum Error: Swift.Error, Sendable {
        case unauthorized
        case notFound
        case rateLimited(resetAt: Date?)
        case network(String)
        case decoding(String)
        case http(Int)
    }

    private let config: Config
    private let session: URLSession
    private let decoder: JSONDecoder

    init(config: Config) {
        self.config = config

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    // MARK: - Public API

    func fetchHealth(defaultBranch: String?) async -> GitHubFetchResult {
        var issues: [FleetIssue] = []
        var health = GitHubHealth(defaultBranch: defaultBranch ?? "main")

        // 1) Resolve default branch if missing.
        var branch = defaultBranch
        if branch == nil {
            do {
                let repo: RepoDTO = try await get("/repos/\(config.owner)/\(config.repo)")
                branch = repo.default_branch
                health.defaultBranch = repo.default_branch
            } catch {
                branch = "main"
                health.defaultBranch = "main"
                issues.append(
                    FleetIssue(
                        severity: severity(for: error, fallback: .warning),
                        source: .github,
                        message: "Could not resolve default branch; assuming 'main'. \(describe(error))"
                    )
                )
            }
        }

        let resolvedBranch = branch ?? "main"

        // 2) Last commit on default branch.
        do {
            let path = "/repos/\(config.owner)/\(config.repo)/commits"
            let commits: [CommitDTO] = try await get(
                path,
                query: [
                    URLQueryItem(name: "sha", value: resolvedBranch),
                    URLQueryItem(name: "per_page", value: "1")
                ]
            )
            if let c = commits.first {
                health.lastCommitSHA = c.sha
                health.lastCommitMessage = c.commit.message
                health.lastCommitAuthor = c.commit.author?.name ?? c.author?.login
                health.lastCommitAt = c.commit.author?.date ?? c.commit.committer?.date
            }
        } catch {
            issues.append(
                FleetIssue(
                    severity: severity(for: error, fallback: .warning),
                    source: .github,
                    message: "Failed to fetch last commit: \(describe(error))"
                )
            )
        }

        // 3) Open PR count.
        do {
            let path = "/repos/\(config.owner)/\(config.repo)/pulls"
            let prs: [PullDTO] = try await get(
                path,
                query: [
                    URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "per_page", value: "100")
                ]
            )
            health.openPRCount = prs.count
        } catch {
            issues.append(
                FleetIssue(
                    severity: severity(for: error, fallback: .warning),
                    source: .github,
                    message: "Failed to fetch open PRs: \(describe(error))"
                )
            )
        }

        // 4) Last workflow run.
        do {
            let path = "/repos/\(config.owner)/\(config.repo)/actions/runs"
            let runs: WorkflowRunsDTO = try await get(
                path,
                query: [
                    URLQueryItem(name: "branch", value: resolvedBranch),
                    URLQueryItem(name: "per_page", value: "1")
                ]
            )
            if let r = runs.workflow_runs.first {
                health.lastWorkflowConclusion = r.conclusion
                health.lastWorkflowRunAt = r.updated_at
            }
        } catch {
            issues.append(
                FleetIssue(
                    severity: severity(for: error, fallback: .warning),
                    source: .github,
                    message: "Failed to fetch workflow runs: \(describe(error))"
                )
            )
        }

        return GitHubFetchResult(health: health, issues: issues)
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var comps = URLComponents(string: "https://api.github.com")!
        comps.path = path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else {
            throw Error.network("Invalid URL for \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MasterConfig-Fleet", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw Error.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Error.network("Not an HTTP response")
        }

        try throwIfFailed(status: http.statusCode, headers: http.allHeaderFields)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Error.decoding(String(describing: error))
        }
    }

    private func throwIfFailed(status: Int, headers: [AnyHashable: Any]) throws {
        guard status >= 400 else { return }

        switch status {
        case 401:
            throw Error.unauthorized
        case 403:
            if let remaining = headers["X-RateLimit-Remaining"] as? String, remaining == "0" {
                throw Error.rateLimited(resetAt: rateLimitResetDate(from: headers))
            }
            throw Error.unauthorized
        case 404:
            throw Error.notFound
        case 429:
            throw Error.rateLimited(resetAt: rateLimitResetDate(from: headers))
        default:
            throw Error.http(status)
        }
    }

    private func rateLimitResetDate(from headers: [AnyHashable: Any]) -> Date? {
        if let resetString = headers["X-RateLimit-Reset"] as? String,
           let epoch = TimeInterval(resetString) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    // MARK: - Issue helpers

    private func severity(for error: Swift.Error, fallback: FleetIssueSeverity) -> FleetIssueSeverity {
        if let e = error as? Error {
            switch e {
            case .unauthorized, .notFound:
                return .critical
            case .rateLimited:
                return .warning
            case .http(let code):
                return code >= 500 ? .warning : .critical
            case .network, .decoding:
                return .warning
            }
        }
        return fallback
    }

    private func describe(_ error: Swift.Error) -> String {
        if let e = error as? Error {
            switch e {
            case .unauthorized:           return "unauthorized (check token scopes)"
            case .notFound:               return "resource not found"
            case .rateLimited(let reset):
                if let r = reset { return "rate limited until \(r)" }
                return "rate limited"
            case .network(let msg):       return "network: \(msg)"
            case .decoding(let msg):      return "decoding: \(msg)"
            case .http(let code):         return "HTTP \(code)"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - DTOs

private struct RepoDTO: Decodable, Sendable {
    let default_branch: String
}

private struct CommitDTO: Decodable, Sendable {
    let sha: String
    let commit: CommitInner
    let author: AuthorLogin?

    struct CommitInner: Decodable, Sendable {
        let message: String
        let author: GitActor?
        let committer: GitActor?
    }

    struct GitActor: Decodable, Sendable {
        let name: String?
        let email: String?
        let date: Date?
    }

    struct AuthorLogin: Decodable, Sendable {
        let login: String?
    }
}

private struct PullDTO: Decodable, Sendable {
    let id: Int
}

private struct WorkflowRunsDTO: Decodable, Sendable {
    let workflow_runs: [WorkflowRunDTO]
}

private struct WorkflowRunDTO: Decodable, Sendable {
    let conclusion: String?
    let updated_at: Date?
}
