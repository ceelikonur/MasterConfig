import Foundation
import UserNotifications

// MARK: - Governance Service

@Observable
@MainActor
final class GovernanceService {

    // Published state
    var pendingApprovals:  [ApprovalRequest] = []
    var decidedApprovals:  [ApprovalRequest] = []
    var governanceConfig:  GovernanceConfig  = GovernanceConfig()
    var isLoading = false

    /// Injected dependency for activity logging
    var activityService: ActivityService?

    // Sidebar badge
    var pendingCount: Int { pendingApprovals.count }

    private let fm = FileManager.default

    // MARK: - Paths

    private var baseDir:    String { NSHomeDirectory() + "/.claude/orchestrator/approvals" }
    private var pendingDir: String { baseDir + "/pending" }
    private var decidedDir: String { baseDir + "/decided" }
    private var configFile: String { baseDir + "/config.json" }

    // MARK: - Bootstrap

    func load() {
        isLoading = true
        defer { isLoading = false }
        ensureDirs()
        loadConfig()
        loadPending()
        loadDecided(limit: 50)
    }

    private func ensureDirs() {
        [baseDir, pendingDir, decidedDir].forEach {
            try? fm.createDirectory(atPath: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: - Loaders

    private func loadConfig() {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
            let cfg  = try? JSONDecoder.iso.decode(GovernanceConfig.self, from: data)
        else { return }
        governanceConfig = cfg
    }

    private func loadPending() {
        pendingApprovals = loadRequests(from: pendingDir)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func loadDecided(limit: Int = 50) {
        decidedApprovals = loadRequests(from: decidedDir)
            .sorted { ($0.decidedAt ?? $0.createdAt) > ($1.decidedAt ?? $1.createdAt) }
            .prefix(limit)
            .map { $0 }
    }

    private func loadRequests(from dir: String) -> [ApprovalRequest] {
        let url = URL(fileURLWithPath: dir)
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".tmp") }
            .compactMap { try? JSONDecoder.iso.decode(ApprovalRequest.self, from: Data(contentsOf: $0)) }
    }

    // MARK: - Atomic Write

    private func atomicWrite(_ data: Data, to path: String) {
        let tmp  = URL(fileURLWithPath: path + ".tmp")
        let dest = URL(fileURLWithPath: path)
        try? data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: path) {
            _ = try? fm.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try? fm.moveItem(at: tmp, to: dest)
        }
    }

    private func saveRequest(_ req: ApprovalRequest, inPending: Bool) {
        let dir  = inPending ? pendingDir : decidedDir
        let path = dir + "/\(req.id).json"
        guard let data = try? JSONEncoder.iso.encode(req) else { return }
        atomicWrite(data, to: path)
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder.iso.encode(governanceConfig) else { return }
        atomicWrite(data, to: configFile)
    }

    // MARK: - CRUD

    @discardableResult
    func createRequest(
        type: ApprovalType,
        title: String,
        description: String = "",
        requestedBy: String,
        metadata: [String: String] = [:]
    ) -> ApprovalRequest {
        let req = ApprovalRequest(
            type: type, title: title, description: description,
            requestedBy: requestedBy, metadata: metadata
        )
        pendingApprovals.insert(req, at: 0)
        saveRequest(req, inPending: true)
        sendNotification(for: req)
        activityService?.log(
            type: .approvalRequested,
            actor: requestedBy,
            summary: "Approval requested: \(title)",
            metadata: ["type": type.label, "id": req.id]
        )
        return req
    }

    func decide(requestId: String, action: ApprovalAction, notes: String? = nil) {
        guard let idx = pendingApprovals.firstIndex(where: { $0.id == requestId }) else { return }

        var req      = pendingApprovals[idx]
        let decision = ApprovalDecision(action: action, notes: notes)
        req.decision  = decision
        req.decidedAt = Date()
        req.status    = {
            switch action {
            case .approve:         return .approved
            case .reject:          return .rejected
            case .requestRevision: return .revisionRequested
            }
        }()

        // Remove from pending, save to decided
        pendingApprovals.remove(at: idx)
        let pendingPath = pendingDir + "/\(req.id).json"
        try? fm.removeItem(atPath: pendingPath)

        decidedApprovals.insert(req, at: 0)
        if decidedApprovals.count > 100 { decidedApprovals = Array(decidedApprovals.prefix(100)) }
        saveRequest(req, inPending: false)
        activityService?.log(
            type: .approvalDecided,
            actor: "board",
            summary: "Approval \(req.status.label.lowercased()): \(req.title)",
            metadata: ["action": action.rawValue, "id": req.id, "by": req.requestedBy]
        )
    }

    // MARK: - Config

    func setApprovalRequired(_ type: ApprovalType, required: Bool) {
        if required {
            governanceConfig.requiredApprovalTypes.insert(type.rawValue)
        } else {
            governanceConfig.requiredApprovalTypes.remove(type.rawValue)
        }
        saveConfig()
    }

    func isRequired(_ type: ApprovalType) -> Bool {
        governanceConfig.requiredApprovalTypes.contains(type.rawValue)
    }

    // MARK: - macOS Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(for req: ApprovalRequest) {
        let content      = UNMutableNotificationContent()
        content.title    = "⏳ Approval Required"
        content.body     = "\(req.requestedBy) → \(req.title)"
        content.sound    = .default
        content.categoryIdentifier = "APPROVAL_REQUEST"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request  = UNNotificationRequest(
            identifier: "approval-\(req.id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Query Helpers

    func request(id: String) -> ApprovalRequest? {
        pendingApprovals.first  { $0.id == id } ??
        decidedApprovals.first  { $0.id == id }
    }
}
