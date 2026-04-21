import Foundation

// MARK: - Result

struct NetlifyFetchResult: Sendable {
    var health: NetlifyHealth
    var issues: [FleetIssue]
}

// MARK: - Netlify Client

actor NetlifyClient {

    struct Config: Sendable {
        let siteId: String
        let token: String
    }

    enum Error: Swift.Error, Sendable {
        case unauthorized
        case notFound
        case rateLimited
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

    func fetchHealth() async -> NetlifyFetchResult {
        var issues: [FleetIssue] = []
        var health = NetlifyHealth()

        do {
            let deploys: [DeployDTO] = try await get(
                "/sites/\(config.siteId)/deploys",
                query: [URLQueryItem(name: "per_page", value: "1")]
            )
            if let d = deploys.first {
                health.lastDeployState = d.state
                health.lastDeployBranch = d.branch
                health.lastDeployAt = d.published_at ?? d.created_at
                health.lastDeployURL = d.deploy_ssl_url ?? d.deploy_url
                health.lastDeployErrorMessage = d.error_message

                if d.state == "error" {
                    issues.append(
                        FleetIssue(
                            severity: .critical,
                            source: .netlify,
                            message: d.error_message ?? "Last deploy failed"
                        )
                    )
                } else if d.state == "building" {
                    issues.append(
                        FleetIssue(
                            severity: .info,
                            source: .netlify,
                            message: "Build in progress"
                        )
                    )
                }
            }
        } catch {
            issues.append(
                FleetIssue(
                    severity: severity(for: error),
                    source: .netlify,
                    message: "Failed to fetch deploys: \(describe(error))"
                )
            )
        }

        return NetlifyFetchResult(health: health, issues: issues)
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var comps = URLComponents(string: "https://api.netlify.com/api/v1")!
        comps.path = "/api/v1" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else {
            throw Error.network("Invalid URL for \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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
        try throwIfFailed(status: http.statusCode)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Error.decoding(String(describing: error))
        }
    }

    private func throwIfFailed(status: Int) throws {
        guard status >= 400 else { return }
        switch status {
        case 401, 403: throw Error.unauthorized
        case 404:      throw Error.notFound
        case 429:      throw Error.rateLimited
        default:       throw Error.http(status)
        }
    }

    // MARK: - Issue helpers

    private func severity(for error: Swift.Error) -> FleetIssueSeverity {
        if let e = error as? Error {
            switch e {
            case .unauthorized, .notFound: return .critical
            case .rateLimited:              return .warning
            case .http(let code):           return code >= 500 ? .warning : .critical
            case .network, .decoding:       return .warning
            }
        }
        return .warning
    }

    private func describe(_ error: Swift.Error) -> String {
        if let e = error as? Error {
            switch e {
            case .unauthorized:      return "unauthorized (check PAT)"
            case .notFound:          return "site not found"
            case .rateLimited:       return "rate limited"
            case .network(let msg):  return "network: \(msg)"
            case .decoding(let msg): return "decoding: \(msg)"
            case .http(let code):    return "HTTP \(code)"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - DTOs

private struct DeployDTO: Decodable, Sendable {
    let state: String?
    let branch: String?
    let created_at: Date?
    let published_at: Date?
    let deploy_url: String?
    let deploy_ssl_url: String?
    let error_message: String?
}
