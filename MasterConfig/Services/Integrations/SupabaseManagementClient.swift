import Foundation

// MARK: - Result

struct SupabaseFetchResult: Sendable {
    var health: SupabaseHealth
    var issues: [FleetIssue]
}

// MARK: - Supabase Management Client

actor SupabaseManagementClient {

    struct Config: Sendable {
        let projectRef: String
        let token: String
    }

    enum Error: Swift.Error, Sendable {
        case unauthorized
        case notFound
        case forbidden
        case network(String)
        case decoding(String)
        case http(Int)
    }

    private let config: Config
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(config: Config) {
        self.config = config

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d

        let e = JSONEncoder()
        self.encoder = e
    }

    // MARK: - Public API

    func fetchHealth() async -> SupabaseFetchResult {
        var issues: [FleetIssue] = []
        var health = SupabaseHealth(lastCheckedAt: Date())

        // 1) Project status.
        do {
            let project: ProjectDTO = try await getJSON(path: "/v1/projects/\(config.projectRef)")
            health.projectStatus = project.status
        } catch {
            issues.append(
                FleetIssue(
                    severity: severity(for: error, fallback: .warning),
                    source: .supabase,
                    message: "Failed to fetch project status: \(describe(error))"
                )
            )
        }

        // 2) RLS introspection.
        let sql = """
        SELECT schemaname, tablename, rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public';
        """
        do {
            let rows: [RLSRow] = try await postQuery(sql: sql)
            health.tableCount = rows.count
            health.rlsDisabledTables = rows
                .filter { $0.rowsecurity == false }
                .map { "\($0.schemaname).\($0.tablename)" }
                .sorted()
        } catch {
            let sev: FleetIssueSeverity
            if case Error.forbidden = error {
                sev = .info
            } else {
                sev = severity(for: error, fallback: .warning)
            }
            let msg: String
            if case Error.forbidden = error {
                msg = "Database introspection not available on this plan"
            } else {
                msg = "Failed to introspect RLS: \(describe(error))"
            }
            issues.append(FleetIssue(severity: sev, source: .supabase, message: msg))
        }

        health.lastCheckedAt = Date()
        return SupabaseFetchResult(health: health, issues: issues)
    }

    // MARK: - HTTP helpers

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: "https://api.supabase.com" + path) else {
            throw Error.network("Invalid URL for \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("MasterConfig-Fleet", forHTTPHeaderField: "User-Agent")
        return try await perform(req)
    }

    private func postQuery<T: Decodable>(sql: String) async throws -> T {
        guard let url = URL(string: "https://api.supabase.com/v1/projects/\(config.projectRef)/database/query") else {
            throw Error.network("Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MasterConfig-Fleet", forHTTPHeaderField: "User-Agent")

        let body = QueryBody(query: sql)
        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            throw Error.decoding(String(describing: error))
        }
        return try await perform(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
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
        case 401:            throw Error.unauthorized
        case 403:            throw Error.forbidden
        case 404:            throw Error.notFound
        default:             throw Error.http(status)
        }
    }

    // MARK: - Issue helpers

    private func severity(for error: Swift.Error, fallback: FleetIssueSeverity) -> FleetIssueSeverity {
        if let e = error as? Error {
            switch e {
            case .unauthorized, .notFound: return .critical
            case .forbidden:                return .info
            case .http(let code):           return code >= 500 ? .warning : .critical
            case .network, .decoding:       return .warning
            }
        }
        return fallback
    }

    private func describe(_ error: Swift.Error) -> String {
        if let e = error as? Error {
            switch e {
            case .unauthorized:        return "unauthorized (check PAT)"
            case .forbidden:           return "forbidden"
            case .notFound:            return "project not found"
            case .network(let msg):    return "network: \(msg)"
            case .decoding(let msg):   return "decoding: \(msg)"
            case .http(let code):      return "HTTP \(code)"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - DTOs

private struct QueryBody: Encodable, Sendable {
    let query: String
}

private struct ProjectDTO: Decodable, Sendable {
    let status: String?
}

private struct RLSRow: Decodable, Sendable {
    let schemaname: String
    let tablename: String
    let rowsecurity: Bool
}
