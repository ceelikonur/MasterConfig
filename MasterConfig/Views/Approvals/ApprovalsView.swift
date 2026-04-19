import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary     = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let surface       = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent        = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary   = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let divider       = Color(red: 0.18, green: 0.20, blue: 0.28)
    static let approveGreen  = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let rejectRed     = Color(red: 0.97, green: 0.40, blue: 0.40)
    static let reviseYellow  = Color(red: 0.97, green: 0.80, blue: 0.35)
    static let pendingBlue   = Color(red: 0.48, green: 0.64, blue: 0.97)
}

private extension ApprovalStatus {
    var uiColor: Color {
        switch self {
        case .pending:           return .pendingBlue
        case .approved:          return .approveGreen
        case .rejected:          return .rejectRed
        case .revisionRequested: return .reviseYellow
        }
    }
}

private extension ApprovalType {
    var uiColor: Color {
        switch self {
        case .agentHire:       return Color(red: 0.76, green: 0.50, blue: 0.97)
        case .budgetChange:    return Color(red: 0.97, green: 0.80, blue: 0.35)
        case .strategyChange:  return Color(red: 0.48, green: 0.64, blue: 0.97)
        case .highRiskAction:  return Color(red: 0.97, green: 0.40, blue: 0.40)
        case .projectCreation: return Color(red: 0.62, green: 0.81, blue: 0.42)
        case .deployment:      return Color(red: 0.97, green: 0.60, blue: 0.35)
        }
    }
}

// MARK: - ApprovalsView

enum ApprovalFilter: String, CaseIterable {
    case all     = "All"
    case pending = "Pending"
    case decided = "Decided"
}

struct ApprovalsView: View {
    @Environment(GovernanceService.self) private var governance
    @Environment(FileWatcherService.self) private var fileWatcher

    @State private var selectedRequest: ApprovalRequest? = nil
    @State private var filter: ApprovalFilter = .pending
    @State private var notesText = ""
    @State private var watchToken: WatchToken? = nil
    @State private var showConfigPanel = false

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            centerPanel
                .frame(minWidth: 360)
            if showConfigPanel {
                configPanel
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            }
        }
        .background(Color.bgPrimary)
        .task { governance.load(); setupWatcher() }
        .onDisappear { if let t = watchToken { fileWatcher.unwatch(t) } }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Left Panel — Request List
    // ─────────────────────────────────────────────────────────────

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Approvals")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                if governance.pendingCount > 0 {
                    Text("\(governance.pendingCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.rejectRed)
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    withAnimation { showConfigPanel.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(showConfigPanel ? Color.accent : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Governance Config")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Filter tabs
            Picker("Filter", selection: $filter) {
                ForEach(ApprovalFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider().overlay(Color.divider)

            let displayed = displayedRequests
            if displayed.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.title)
                        .foregroundStyle(Color.textSecondary)
                    Text(filter == .pending ? "No pending approvals" : "No requests yet")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayed) { req in
                            requestRow(req)
                            Divider().overlay(Color.divider).padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .background(Color.bgPrimary)
    }

    private var displayedRequests: [ApprovalRequest] {
        switch filter {
        case .all:     return governance.pendingApprovals + governance.decidedApprovals
        case .pending: return governance.pendingApprovals
        case .decided: return governance.decidedApprovals
        }
    }

    private func requestRow(_ req: ApprovalRequest) -> some View {
        let isSelected = selectedRequest?.id == req.id
        return Button {
            selectedRequest = req
            notesText = ""
        } label: {
            HStack(spacing: 10) {
                // Type icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(req.type.uiColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: req.type.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(req.type.uiColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(req.title)
                        .font(.system(.callout, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(req.requestedBy)
                            .font(.caption2)
                            .foregroundStyle(Color.accent)
                        Text("·")
                            .foregroundStyle(Color.textSecondary)
                        Text(req.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                // Status dot
                Image(systemName: req.status.icon)
                    .font(.caption)
                    .foregroundStyle(req.status.uiColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Center Panel — Detail + Action Bar
    // ─────────────────────────────────────────────────────────────

    private var centerPanel: some View {
        Group {
            if let req = selectedRequest.flatMap({ governance.request(id: $0.id) }) ?? selectedRequest {
                VStack(spacing: 0) {
                    detailContent(req)
                    if req.status == .pending {
                        Divider().overlay(Color.divider)
                        actionBar(req)
                    }
                }
            } else {
                emptyDetail
            }
        }
        .background(Color.bgPrimary)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("Select an approval request")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
            if governance.pendingCount > 0 {
                Text("\(governance.pendingCount) pending review")
                    .font(.callout)
                    .foregroundStyle(Color.rejectRed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(_ req: ApprovalRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(req.type.uiColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: req.type.icon)
                            .font(.title2)
                            .foregroundStyle(req.type.uiColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(req.title)
                            .font(.title3.bold())
                            .foregroundStyle(Color.textPrimary)
                        HStack(spacing: 8) {
                            typeBadge(req.type)
                            statusBadge(req.status)
                        }
                    }
                    Spacer()
                }

                // Description
                if !req.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("Description")
                        Text(req.description)
                            .font(.callout)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface)
                    .cornerRadius(10)
                }

                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Details")
                    metaRow("Requested by", req.requestedBy, icon: "person.circle", color: .accent)
                    metaRow("Type", req.type.label, icon: req.type.icon, color: req.type.uiColor)
                    metaRow("Created", req.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "clock", color: .textSecondary)
                    if let decided = req.decidedAt {
                        metaRow("Decided", decided.formatted(date: .abbreviated, time: .shortened), icon: "checkmark.circle", color: .approveGreen)
                    }
                    if !req.metadata.isEmpty {
                        Divider().overlay(Color.divider)
                        ForEach(req.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            metaRow(key, value, icon: "info.circle", color: .textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(Color.surface)
                .cornerRadius(10)

                // Decision (if decided)
                if let decision = req.decision {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Decision")
                        HStack(spacing: 10) {
                            Image(systemName: req.status.icon)
                                .foregroundStyle(req.status.uiColor)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(req.status.label)
                                    .font(.headline)
                                    .foregroundStyle(req.status.uiColor)
                                Text("by \(decision.decidedBy)")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        if let notes = decision.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.callout)
                                .foregroundStyle(Color.textPrimary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(req.status.uiColor.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(Color.surface)
                    .cornerRadius(10)
                }
            }
            .padding(20)
        }
    }

    private func actionBar(_ req: ApprovalRequest) -> some View {
        VStack(spacing: 12) {
            // Notes field
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.textSecondary)
                    .font(.caption)
                TextField("Add a note with your decision (optional)…", text: $notesText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(10)
            .background(Color.surface)
            .cornerRadius(8)

            // Action buttons
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .approveGreen) {
                    governance.decide(requestId: req.id, action: .approve, notes: notesText.isEmpty ? nil : notesText)
                    notesText = ""
                    selectedRequest = nil
                }
                actionButton("Reject", icon: "xmark.circle.fill", color: .rejectRed) {
                    governance.decide(requestId: req.id, action: .reject, notes: notesText.isEmpty ? nil : notesText)
                    notesText = ""
                    selectedRequest = nil
                }
                actionButton("Revise", icon: "arrow.clockwise.circle.fill", color: .reviseYellow) {
                    governance.decide(requestId: req.id, action: .requestRevision, notes: notesText.isEmpty ? nil : notesText)
                    notesText = ""
                    selectedRequest = nil
                }
            }
        }
        .padding(16)
        .background(Color.surface)
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color)
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Right Panel — Governance Config
    // ─────────────────────────────────────────────────────────────

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Governance")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { withAnimation { showConfigPanel = false } } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider().overlay(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Require approval for:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)

                    ForEach(ApprovalType.allCases, id: \.self) { type in
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .font(.caption)
                                .foregroundStyle(type.uiColor)
                                .frame(width: 18)
                            Text(type.label)
                                .font(.callout)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { governance.isRequired(type) },
                                set: { governance.setApprovalRequired(type, required: $0) }
                            ))
                            .toggleStyle(.switch)
                            .tint(type.uiColor)
                            .labelsHidden()
                            .scaleEffect(0.8)
                        }
                        .padding(10)
                        .background(Color.surface)
                        .cornerRadius(8)
                    }

                    Divider().overlay(Color.divider)

                    // Stats
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stats")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        statRow("Pending", "\(governance.pendingCount)", color: .rejectRed)
                        statRow("Decided (recent)", "\(governance.decidedApprovals.count)", color: .approveGreen)
                        let approvedCount = governance.decidedApprovals.filter { $0.status == .approved }.count
                        let rejectedCount = governance.decidedApprovals.filter { $0.status == .rejected }.count
                        statRow("Approved", "\(approvedCount)", color: .approveGreen)
                        statRow("Rejected", "\(rejectedCount)", color: .rejectRed)
                    }
                }
                .padding(14)
            }
        }
        .background(Color.bgPrimary)
    }

    private func statRow(_ key: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(key).font(.caption2).foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value).font(.caption2.bold()).foregroundStyle(color)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Shared Helpers
    // ─────────────────────────────────────────────────────────────

    private func typeBadge(_ type: ApprovalType) -> some View {
        Label(type.label, systemImage: type.icon)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(type.uiColor.opacity(0.15))
            .foregroundStyle(type.uiColor)
            .cornerRadius(5)
    }

    private func statusBadge(_ status: ApprovalStatus) -> some View {
        Label(status.label, systemImage: status.icon)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.uiColor.opacity(0.15))
            .foregroundStyle(status.uiColor)
            .cornerRadius(5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
    }

    private func metaRow(_ key: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - File Watcher

    private func setupWatcher() {
        let path = NSHomeDirectory() + "/.claude/orchestrator/approvals"
        watchToken = fileWatcher.watch(path) { [self] in
            governance.load()
        }
    }
}
