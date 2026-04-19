import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary      = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let surface        = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let surfaceHover   = Color(red: 0.16, green: 0.17, blue: 0.22)
    static let accent         = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary    = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary  = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let divider        = Color(red: 0.18, green: 0.20, blue: 0.28)
    static let statusBacklog  = Color(red: 0.34, green: 0.37, blue: 0.54)
    static let statusTodo     = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let statusProgress = Color(red: 0.97, green: 0.70, blue: 0.35)
    static let statusReview   = Color(red: 0.76, green: 0.50, blue: 0.97)
    static let statusDone     = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let priorityLow    = Color(red: 0.34, green: 0.37, blue: 0.54)
    static let priorityNormal = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let priorityHigh   = Color(red: 0.97, green: 0.70, blue: 0.35)
    static let priorityUrgent = Color(red: 0.97, green: 0.40, blue: 0.40)
}

private extension IssueStatus {
    var uiColor: Color {
        switch self {
        case .backlog:    return .statusBacklog
        case .todo:       return .statusTodo
        case .inProgress: return .statusProgress
        case .review:     return .statusReview
        case .done:       return .statusDone
        }
    }
}

private extension IssuePriority {
    var uiColor: Color {
        switch self {
        case .low:    return .priorityLow
        case .normal: return .priorityNormal
        case .high:   return .priorityHigh
        case .urgent: return .priorityUrgent
        }
    }
}

// MARK: - TasksView (3-panel hierarchical layout)

struct TasksView: View {
    @Environment(HierarchyService.self) private var hierarchy
    @Environment(FileWatcherService.self) private var fileWatcher

    @State private var selectedContext: IssueContext = .all
    @State private var selectedIssue: Issue?
    @State private var showNewIssueSheet  = false
    @State private var showNewGoalSheet   = false
    @State private var showNewProjectSheet = false
    @State private var showNewMilestoneSheet = false
    @State private var expandedGoals:    Set<String> = []
    @State private var expandedProjects: Set<String> = []
    @State private var watchToken: WatchToken?
    @State private var newCommentText = ""

    private let issuesDir: String = NSHomeDirectory() + "/.claude/orchestrator/issues"

    var body: some View {
        HSplitView {
            hierarchyPanel
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            issueListPanel
                .frame(minWidth: 300, idealWidth: 420)
            if let issue = selectedIssue {
                issueDetailPanel(issue)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            }
        }
        .background(Color.bgPrimary)
        .task { hierarchy.load(); setupWatcher() }
        .onDisappear { if let t = watchToken { fileWatcher.unwatch(t) } }
        .sheet(isPresented: $showNewIssueSheet) {
            NewIssueSheet(hierarchy: hierarchy, context: selectedContext)
        }
        .sheet(isPresented: $showNewGoalSheet) {
            NewGoalSheet(hierarchy: hierarchy)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(hierarchy: hierarchy, selectedContext: selectedContext)
        }
        .sheet(isPresented: $showNewMilestoneSheet) {
            NewMilestoneSheet(hierarchy: hierarchy, selectedContext: selectedContext)
        }
        .onKeyPress(.init("n"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                showNewIssueSheet = true
                return .handled
            }
            return .ignored
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Left Panel — Hierarchy Tree
    // ─────────────────────────────────────────────────────────────

    private var hierarchyPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Hierarchy")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Menu {
                    Button("New Goal")      { showNewGoalSheet = true }
                    Button("New Project")   { showNewProjectSheet = true }
                    Button("New Milestone") { showNewMilestoneSheet = true }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // All Issues
                    contextRow(
                        icon: "tray.full", label: "All Issues",
                        count: hierarchy.issues.count,
                        context: .all
                    )

                    Divider().overlay(Color.divider).padding(.vertical, 4)

                    if hierarchy.goals.isEmpty {
                        Text("No goals yet")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(hierarchy.goals) { goal in
                            goalRow(goal)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color.bgPrimary)
    }

    private func contextRow(icon: String, label: String, count: Int, context: IssueContext) -> some View {
        Button {
            selectedContext = context
            selectedIssue = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(selectedContext == context ? Color.accent : Color.textSecondary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(.body, weight: selectedContext == context ? .semibold : .regular))
                    .foregroundStyle(selectedContext == context ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(selectedContext == context ? Color.accent.opacity(0.12) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func goalRow(_ goal: Goal) -> some View {
        let isExpanded = expandedGoals.contains(goal.id)
        let issueCount = hierarchy.issues(for: .goal(goal.id)).count

        return VStack(alignment: .leading, spacing: 0) {
            // Goal header
            HStack(spacing: 6) {
                Button {
                    if isExpanded { expandedGoals.remove(goal.id) }
                    else          { expandedGoals.insert(goal.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 10)
                }
                .buttonStyle(.plain)

                Button {
                    selectedContext = .goal(goal.id)
                    selectedIssue = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.caption)
                            .foregroundStyle(Color.accent)
                            .frame(width: 14)
                        Text(goal.title)
                            .font(.system(.body, weight: selectedContext == .goal(goal.id) ? .semibold : .medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if issueCount > 0 {
                            Text("\(issueCount)")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .background(selectedContext == .goal(goal.id) ? Color.accent.opacity(0.12) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.trailing, 4)

            // Projects
            if isExpanded {
                let goalProjects = hierarchy.projects(for: goal.id)
                ForEach(goalProjects) { project in
                    projectRow(project)
                        .padding(.leading, 18)
                }
                if goalProjects.isEmpty {
                    Text("No projects")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, 34)
                        .padding(.vertical, 3)
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let isExpanded = expandedProjects.contains(project.id)
        let issueCount = hierarchy.issues(for: .project(project.id)).count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if isExpanded { expandedProjects.remove(project.id) }
                    else          { expandedProjects.insert(project.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 10)
                }
                .buttonStyle(.plain)

                Button {
                    selectedContext = .project(project.id)
                    selectedIssue = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(Color.statusTodo)
                            .frame(width: 14)
                        Text(project.title)
                            .font(.system(.callout, weight: selectedContext == .project(project.id) ? .semibold : .regular))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if issueCount > 0 {
                            Text("\(issueCount)")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(selectedContext == .project(project.id) ? Color.accent.opacity(0.12) : Color.clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            // Milestones
            if isExpanded {
                let projectMilestones = hierarchy.milestones(for: project.id)
                ForEach(projectMilestones) { milestone in
                    milestoneRow(milestone)
                        .padding(.leading, 18)
                }
                if projectMilestones.isEmpty {
                    Text("No milestones")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, 20)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func milestoneRow(_ milestone: Milestone) -> some View {
        let issueCount = hierarchy.issues(for: .milestone(milestone.id)).count
        return Button {
            selectedContext = .milestone(milestone.id)
            selectedIssue = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: milestone.status == .closed ? "flag.fill" : "flag")
                    .font(.caption)
                    .foregroundStyle(milestone.status == .closed ? Color.statusDone : Color.statusProgress)
                    .frame(width: 14)
                Text(milestone.title)
                    .font(.caption)
                    .foregroundStyle(selectedContext == .milestone(milestone.id) ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                if issueCount > 0 {
                    Text("\(issueCount)")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selectedContext == .milestone(milestone.id) ? Color.accent.opacity(0.12) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Middle Panel — Issue List
    // ─────────────────────────────────────────────────────────────

    private var issueListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                contextTitle
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { showNewIssueSheet = true } label: {
                    Label("New Issue", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .help("New Issue (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Color.divider)

            let contextIssues = hierarchy.issues(for: selectedContext)

            if contextIssues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textSecondary)
                    Text("No issues")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                    Button("Create Issue") { showNewIssueSheet = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(IssueStatus.allCases, id: \.self) { status in
                            let statusIssues = contextIssues.filter { $0.status == status }
                            if !statusIssues.isEmpty {
                                Section {
                                    ForEach(statusIssues) { issue in
                                        issueRow(issue)
                                    }
                                } header: {
                                    issueGroupHeader(status: status, count: statusIssues.count)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.bgPrimary)
    }

    private var contextTitle: some View {
        Group {
            switch selectedContext {
            case .all:
                Text("All Issues")
            case .goal(let id):
                Text(hierarchy.goals.first { $0.id == id }?.title ?? "Goal")
            case .project(let id):
                Text(hierarchy.projects.first { $0.id == id }?.title ?? "Project")
            case .milestone(let id):
                Text(hierarchy.milestones.first { $0.id == id }?.title ?? "Milestone")
            }
        }
    }

    private func issueGroupHeader(status: IssueStatus, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
                .font(.caption)
                .foregroundStyle(status.uiColor)
            Text(status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgPrimary)
    }

    private func issueRow(_ issue: Issue) -> some View {
        Button {
            selectedIssue = issue
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: issue.status.icon)
                    .font(.caption)
                    .foregroundStyle(issue.status.uiColor)
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.system(.body, weight: selectedIssue?.id == issue.id ? .semibold : .regular))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        // Priority badge
                        Label(issue.priority.label, systemImage: issue.priority.icon)
                            .font(.caption2)
                            .foregroundStyle(issue.priority.uiColor)

                        // Assignee
                        if let assignee = issue.assignee, !assignee.isEmpty {
                            Text("@\(assignee)")
                                .font(.caption2)
                                .foregroundStyle(Color.accent)
                        }

                        // Labels
                        ForEach(issue.labels.prefix(2), id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accent.opacity(0.12))
                                .foregroundStyle(Color.accent)
                                .cornerRadius(3)
                        }

                        Spacer()

                        // Comment count
                        if !issue.comments.isEmpty {
                            Label("\(issue.comments.count)", systemImage: "bubble.left")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedIssue?.id == issue.id ? Color.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            issueContextMenu(issue)
        }
    }

    @ViewBuilder
    private func issueContextMenu(_ issue: Issue) -> some View {
        Menu("Set Status") {
            ForEach(IssueStatus.allCases, id: \.self) { status in
                Button(status.label) {
                    hierarchy.updateIssue(issue.id, status: status)
                    if selectedIssue?.id == issue.id {
                        selectedIssue = hierarchy.issues.first { $0.id == issue.id }
                    }
                }
            }
        }
        Menu("Set Priority") {
            ForEach(IssuePriority.allCases, id: \.self) { priority in
                Button(priority.label) {
                    hierarchy.updateIssue(issue.id, priority: priority)
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            if selectedIssue?.id == issue.id { selectedIssue = nil }
            hierarchy.deleteIssue(issue.id)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Right Panel — Issue Detail
    // ─────────────────────────────────────────────────────────────

    private func issueDetailPanel(_ issue: Issue) -> some View {
        // Keep live reference
        let live = hierarchy.issues.first { $0.id == issue.id } ?? issue

        return VStack(spacing: 0) {
            // Title header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: live.status.icon)
                        .foregroundStyle(live.status.uiColor)
                    Text(live.title)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Button { selectedIssue = nil } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.textSecondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                // Meta row
                HStack(spacing: 10) {
                    statusPill(live.status)
                    priorityPill(live.priority)
                    if let assignee = live.assignee, !assignee.isEmpty {
                        Text("@\(assignee)")
                            .font(.caption2)
                            .foregroundStyle(Color.accent)
                    }
                }

                if !live.labels.isEmpty {
                    HStack {
                        ForEach(live.labels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accent.opacity(0.12))
                                .foregroundStyle(Color.accent)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(14)

            Divider().overlay(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    if !live.description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(live.description)
                                .font(.callout)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Status changer
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        HStack(spacing: 6) {
                            ForEach(IssueStatus.allCases, id: \.self) { st in
                                Button {
                                    hierarchy.updateIssue(live.id, status: st)
                                    selectedIssue = hierarchy.issues.first { $0.id == live.id }
                                } label: {
                                    Text(st.label)
                                        .font(.caption2)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(live.status == st ? st.uiColor.opacity(0.25) : Color.surface)
                                        .foregroundStyle(live.status == st ? st.uiColor : Color.textSecondary)
                                        .cornerRadius(5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(live.status == st ? st.uiColor.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Info")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        metaRow("Created by", live.createdBy)
                        metaRow("Created", live.createdAt.formatted(date: .abbreviated, time: .shortened))
                        metaRow("Updated", live.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        if let pid = live.projectId,
                           let project = hierarchy.projects.first(where: { $0.id == pid }) {
                            metaRow("Project", project.title)
                        }
                        if let mid = live.milestoneId,
                           let milestone = hierarchy.milestones.first(where: { $0.id == mid }) {
                            metaRow("Milestone", milestone.title)
                        }
                    }

                    Divider().overlay(Color.divider)

                    // Comments
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comments (\(live.comments.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)

                        ForEach(live.comments) { comment in
                            commentBubble(comment)
                        }

                        // Add comment
                        HStack(alignment: .bottom, spacing: 8) {
                            TextEditor(text: $newCommentText)
                                .font(.callout)
                                .frame(minHeight: 44, maxHeight: 100)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color.surface)
                                .cornerRadius(8)
                                .foregroundStyle(Color.textPrimary)

                            Button {
                                let body = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !body.isEmpty else { return }
                                hierarchy.addComment(to: live.id, author: "board", body: body)
                                newCommentText = ""
                                selectedIssue = hierarchy.issues.first { $0.id == live.id }
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.textSecondary : Color.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Color.bgPrimary)
    }

    private func statusPill(_ status: IssueStatus) -> some View {
        Label(status.label, systemImage: status.icon)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.uiColor.opacity(0.15))
            .foregroundStyle(status.uiColor)
            .cornerRadius(5)
    }

    private func priorityPill(_ priority: IssuePriority) -> some View {
        Label(priority.label, systemImage: priority.icon)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(priority.uiColor.opacity(0.15))
            .foregroundStyle(priority.uiColor)
            .cornerRadius(5)
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    private func commentBubble(_ comment: IssueComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                Spacer()
                Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(comment.body)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.surface)
        .cornerRadius(8)
    }

    // MARK: - File Watcher

    private func setupWatcher() {
        let path = NSHomeDirectory() + "/.claude/orchestrator"
        watchToken = fileWatcher.watch(path) {
            hierarchy.load()
        }
    }
}

// MARK: - TeamMember + Hashable (backward compat)

extension TaskTeam: Hashable {
    static func == (lhs: TaskTeam, rhs: TaskTeam) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension TeamMember: Hashable {
    static func == (lhs: TeamMember, rhs: TeamMember) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

// MARK: - New Goal Sheet

struct NewGoalSheet: View {
    let hierarchy: HierarchyService
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Goal")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            LabeledContent("Title") {
                TextField("Goal title", text: $title)
                    .textFieldStyle(.plain)
            }
            LabeledContent("Description") {
                TextEditor(text: $description)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard !title.isEmpty else { return }
                    hierarchy.createGoal(title: title, description: description)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    let hierarchy: HierarchyService
    let selectedContext: IssueContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var selectedGoalId: String? = nil

    private var defaultGoalId: String? {
        if case .goal(let id) = selectedContext { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            LabeledContent("Title") {
                TextField("Project title", text: $title)
                    .textFieldStyle(.plain)
            }
            LabeledContent("Description") {
                TextEditor(text: $description)
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
            LabeledContent("Goal (optional)") {
                Picker("Goal", selection: $selectedGoalId) {
                    Text("None").tag(String?.none)
                    ForEach(hierarchy.goals) { goal in
                        Text(goal.title).tag(Optional(goal.id))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard !title.isEmpty else { return }
                    hierarchy.createProject(title: title, description: description, goalId: selectedGoalId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { selectedGoalId = defaultGoalId }
    }
}

// MARK: - New Milestone Sheet

struct NewMilestoneSheet: View {
    let hierarchy: HierarchyService
    let selectedContext: IssueContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedProjectId: String? = nil
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(60 * 60 * 24 * 14)

    private var defaultProjectId: String? {
        if case .project(let id) = selectedContext { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Milestone")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            LabeledContent("Title") {
                TextField("Milestone title", text: $title)
                    .textFieldStyle(.plain)
            }
            LabeledContent("Project") {
                Picker("Project", selection: $selectedProjectId) {
                    Text("None").tag(String?.none)
                    ForEach(hierarchy.projects) { project in
                        Text(project.title).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
            }
            LabeledContent("Due Date") {
                Toggle("Set due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard !title.isEmpty, let pid = selectedProjectId else { return }
                    hierarchy.createMilestone(title: title, projectId: pid, dueDate: hasDueDate ? dueDate : nil)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || selectedProjectId == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { selectedProjectId = defaultProjectId }
    }
}

// MARK: - New Issue Sheet

struct NewIssueSheet: View {
    let hierarchy: HierarchyService
    let context: IssueContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedProjectId: String? = nil
    @State private var selectedMilestoneId: String? = nil
    @State private var assignee = ""
    @State private var priority: IssuePriority = .normal
    @State private var labelsText = ""

    private var defaultProjectId: String? {
        if case .project(let id) = context   { return id }
        return nil
    }
    private var defaultMilestoneId: String? {
        if case .milestone(let id) = context { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Issue")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            LabeledContent("Title") {
                TextField("Issue title", text: $title)
                    .textFieldStyle(.plain)
            }
            LabeledContent("Description") {
                TextEditor(text: $description)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
            LabeledContent("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(IssuePriority.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }
            LabeledContent("Project") {
                Picker("Project", selection: $selectedProjectId) {
                    Text("None").tag(String?.none)
                    ForEach(hierarchy.projects) { p in
                        Text(p.title).tag(Optional(p.id))
                    }
                }
                .pickerStyle(.menu)
            }
            LabeledContent("Milestone") {
                Picker("Milestone", selection: $selectedMilestoneId) {
                    Text("None").tag(String?.none)
                    let mils = selectedProjectId.map { hierarchy.milestones(for: $0) } ?? hierarchy.milestones
                    ForEach(mils) { m in
                        Text(m.title).tag(Optional(m.id))
                    }
                }
                .pickerStyle(.menu)
            }
            LabeledContent("Assignee") {
                TextField("agent-name", text: $assignee)
                    .textFieldStyle(.plain)
            }
            LabeledContent("Labels") {
                TextField("comma, separated", text: $labelsText)
                    .textFieldStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard !title.isEmpty else { return }
                    let labels = labelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    hierarchy.createIssue(
                        title: title, description: description,
                        projectId: selectedProjectId, milestoneId: selectedMilestoneId,
                        assignee: assignee.isEmpty ? nil : assignee,
                        priority: priority, labels: labels
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            selectedProjectId   = defaultProjectId
            selectedMilestoneId = defaultMilestoneId
        }
    }
}
