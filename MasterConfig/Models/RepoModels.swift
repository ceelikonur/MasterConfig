import Foundation

// MARK: - Repo

struct Repo: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var name: String
    var branch: String
    var status: RepoStatus
    var remoteURL: String?
    var hasClaudeMD: Bool
    var claudeMDContent: String?
    var lastCommit: Commit?
}

// MARK: - RepoStatus

enum RepoStatus: String, Codable, CaseIterable, Sendable {
    case clean = "clean"
    case modified = "modified"
    case staged = "staged"
    case untracked = "untracked"
    case ahead = "ahead"
    case behind = "behind"
    case conflict = "conflict"
    case unknown = "unknown"

    var color: String {
        switch self {
        case .clean: return "green"
        case .modified: return "yellow"
        case .staged: return "blue"
        case .untracked: return "orange"
        case .ahead: return "cyan"
        case .behind: return "purple"
        case .conflict: return "red"
        case .unknown: return "gray"
        }
    }

    var label: String {
        switch self {
        case .clean: return "Clean"
        case .modified: return "Modified"
        case .staged: return "Staged"
        case .untracked: return "Untracked"
        case .ahead: return "Ahead"
        case .behind: return "Behind"
        case .conflict: return "Conflict"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Commit

struct Commit: Codable, Hashable, Sendable {
    var hash: String
    var shortHash: String
    var message: String
    var author: String
    var date: Date?
    var dateString: String
}

// MARK: - GitDiff

struct GitDiff: Sendable {
    var added: Int
    var deleted: Int
    var files: [String]
}

// MARK: - GitignoreTemplate

enum GitignoreTemplate: String, CaseIterable, Sendable {
    case none    = "None"
    case node    = "Node.js"
    case python  = "Python"
    case swift   = "Swift"
    case go      = "Go"
    case rust    = "Rust"

    var content: String {
        switch self {
        case .none: return "# .gitignore\n.DS_Store\n*.log\n"
        case .node: return """
            # Node.js
            node_modules/
            dist/
            build/
            .env
            .env.local
            .env.*.local
            npm-debug.log*
            yarn-debug.log*
            yarn-error.log*
            .DS_Store
            *.log
            .cache/
            coverage/
            """
        case .python: return """
            # Python
            __pycache__/
            *.pyc
            *.pyo
            *.pyd
            .venv/
            venv/
            env/
            .env
            *.egg-info/
            dist/
            build/
            .pytest_cache/
            .mypy_cache/
            .DS_Store
            *.log
            """
        case .swift: return """
            # Swift / Xcode
            .build/
            .swiftpm/
            *.xcodeproj/xcuserdata/
            *.xcworkspace/xcuserdata/
            DerivedData/
            *.ipa
            *.dSYM.zip
            *.dSYM
            Pods/
            .DS_Store
            """
        case .go: return """
            # Go
            bin/
            *.exe
            *.exe~
            *.dll
            *.so
            *.dylib
            *.test
            *.out
            vendor/
            .env
            .DS_Store
            """
        case .rust: return """
            # Rust
            target/
            Cargo.lock
            **/*.rs.bk
            .env
            .DS_Store
            """
        }
    }
}
