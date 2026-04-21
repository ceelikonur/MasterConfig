import SwiftUI

// MARK: - Detail View

struct FleetProjectDetailView: View {
    @Environment(FleetService.self) private var fleetService

    let projectId: String
    let onRemoved: () -> Void

    @State private var isRefreshing = false
    @State private var showRemoveAlert = false

    private var project: FleetProject? {
        fleetService.projects.first { $0.id == projectId }
    }

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(project: project)
                        if project.github != nil {
                            githubSection(project: project)
                        }
                        if project.supabase != nil {
                            supabaseSection(project: project)
                        }
                        if project.netlify != nil {
                            netlifySection(project: project)
                        }
                        issuesSection(project: project)
                        dangerZone(project: project)
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                Text("Project not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Remove Project?", isPresented: $showRemoveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                fleetService.removeProject(id: projectId)
                onRemoved()
            }
        } message: {
            Text("This removes the project from your fleet. Keychain tokens remain but become orphaned.")
        }
    }

    // MARK: - Header

    private func headerSection(project: FleetProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                FleetHealthBadge(
                    status: project.lastHealth?.status,
                    score: nil,
                    size: .large
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2.bold())
                    if let client = project.clientName, !client.isEmpty {
                        Text(client)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(project.lastHealth?.status.label ?? "Unknown")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(fleetColor(for: project.lastHealth?.status))
                        if let score = project.lastHealth?.score {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("Score \(score)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let checked = project.lastCheckedAt {
                        Text("Last checked \(checked.formatted(.relative(presentation: .numeric)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Never refreshed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }

                Spacer()

                Button {
                    Task {
                        isRefreshing = true
                        await fleetService.refreshHealth(for: projectId)
                        isRefreshing = false
                    }
                } label: {
                    Label(isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }

            if let notes = project.notes, !notes.isEmpty {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - GitHub Section

    private func githubSection(project: FleetProject) -> some View {
        sectionBox(
            title: "GitHub",
            icon: "chevron.left.forwardslash.chevron.right",
            tint: .purple
        ) {
            if let ref = project.github {
                VStack(alignment: .leading, spacing: 10) {
                    kvRow(key: "Repository", value: "\(ref.owner)/\(ref.repo)")
                    if let branch = ref.defaultBranch, !branch.isEmpty {
                        kvRow(key: "Default Branch", value: branch)
                    } else if let branch = project.lastHealth?.github?.defaultBranch {
                        kvRow(key: "Default Branch", value: branch)
                    }

                    if let gh = project.lastHealth?.github {
                        Divider()
                        if let sha = gh.lastCommitSHA {
                            commitRow(
                                sha: sha,
                                message: gh.lastCommitMessage,
                                author: gh.lastCommitAuthor,
                                at: gh.lastCommitAt
                            )
                        }
                        HStack {
                            Label("\(gh.openPRCount) open", systemImage: "arrow.triangle.pull")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.purple.opacity(0.14)))
                                .foregroundStyle(.purple)
                            if let conclusion = gh.lastWorkflowConclusion {
                                workflowBadge(conclusion: conclusion, at: gh.lastWorkflowRunAt)
                            }
                            Spacer()
                        }
                    } else {
                        emptyHint
                    }
                }
            }
        }
    }

    private func commitRow(sha: String, message: String?, author: String?, at: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(String(sha.prefix(7)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.purple)
                if let author {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let at {
                    Text(at.formatted(.relative(presentation: .numeric)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
    }

    private func workflowBadge(conclusion: String, at: Date?) -> some View {
        let lower = conclusion.lowercased()
        let icon: String
        let color: Color
        switch lower {
        case "success":              icon = "checkmark.circle.fill"; color = .green
        case "failure", "cancelled": icon = "xmark.circle.fill";      color = .red
        default:                     icon = "minus.circle";           color = .gray
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text("CI \(conclusion)")
            if let at {
                Text("· \(at.formatted(.relative(presentation: .numeric)))")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }

    // MARK: - Supabase Section

    private func supabaseSection(project: FleetProject) -> some View {
        sectionBox(
            title: "Supabase",
            icon: "cylinder.split.1x2",
            tint: .green
        ) {
            if let ref = project.supabase {
                VStack(alignment: .leading, spacing: 10) {
                    kvRow(key: "Project Ref", value: ref.projectRef)
                    if let region = ref.region, !region.isEmpty {
                        kvRow(key: "Region", value: region)
                    }

                    if let sb = project.lastHealth?.supabase {
                        Divider()
                        if let status = sb.projectStatus {
                            kvRow(key: "Status", value: status)
                        }
                        if let tc = sb.tableCount {
                            kvRow(key: "Tables", value: "\(tc)")
                        }
                        if !sb.rlsDisabledTables.isEmpty {
                            rlsWarningCard(tables: sb.rlsDisabledTables)
                        }
                    } else {
                        emptyHint
                    }
                }
            }
        }
    }

    private func rlsWarningCard(tables: [String]) -> some View {
        let shown = tables.prefix(5)
        let more  = max(0, tables.count - shown.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                Text("RLS Disabled on \(tables.count) table\(tables.count == 1 ? "" : "s")")
                    .font(.caption.bold())
            }
            .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(shown), id: \.self) { t in
                    Text("• \(t)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                if more > 0 {
                    Text("+ \(more) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Netlify Section

    private func netlifySection(project: FleetProject) -> some View {
        sectionBox(
            title: "Netlify",
            icon: "globe",
            tint: .cyan
        ) {
            if let ref = project.netlify {
                VStack(alignment: .leading, spacing: 10) {
                    kvRow(key: "Site ID", value: ref.siteId)
                    if let name = ref.siteName, !name.isEmpty {
                        kvRow(key: "Site Name", value: name)
                    }

                    if let nf = project.lastHealth?.netlify {
                        Divider()
                        HStack {
                            if let state = nf.lastDeployState {
                                deployStateBadge(state: state)
                            }
                            if let branch = nf.lastDeployBranch {
                                Text(branch)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let at = nf.lastDeployAt {
                                Text(at.formatted(.relative(presentation: .numeric)))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if let urlString = nf.lastDeployURL, let url = URL(string: urlString) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text(urlString)
                                        .lineLimit(1)
                                }
                                .font(.caption)
                            }
                        }
                        if let err = nf.lastDeployErrorMessage, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.10))
                                .cornerRadius(6)
                        }
                    } else {
                        emptyHint
                    }
                }
            }
        }
    }

    private func deployStateBadge(state: String) -> some View {
        let lower = state.lowercased()
        let color: Color
        switch lower {
        case "ready", "current":    color = .green
        case "building", "enqueued": color = .yellow
        case "error", "failed":     color = .red
        default:                    color = .gray
        }
        return Text(state)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    // MARK: - Issues Section

    private func issuesSection(project: FleetProject) -> some View {
        sectionBox(
            title: "Issues",
            icon: "exclamationmark.bubble",
            tint: .orange
        ) {
            let issues = project.lastHealth?.issues ?? []
            if issues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(.green)
                    Text("No issues detected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issues) { issue in
                        issueRow(issue)
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: FleetIssue) -> some View {
        let color = fleetColor(forSeverity: issue.severity)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity.icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.severity.label.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label(issue.source.label, systemImage: issue.source.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(issue.detectedAt.formatted(.relative(presentation: .numeric)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Danger Zone

    private func dangerZone(project: FleetProject) -> some View {
        sectionBox(
            title: "Danger Zone",
            icon: "exclamationmark.octagon",
            tint: .red
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove project")
                        .font(.callout.weight(.semibold))
                    Text("Stops tracking this project. Keychain tokens are left untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    showRemoveAlert = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Shared Building Blocks

    @ViewBuilder
    private func sectionBox<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            content()
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
        }
    }

    private func kvRow(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var emptyHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.tertiary)
            Text("No data yet — tap Refresh")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
