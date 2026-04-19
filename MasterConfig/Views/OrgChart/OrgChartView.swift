import SwiftUI

// MARK: - Layout Constants (file-private)

private let cardW:    CGFloat = 164
private let cardH:    CGFloat = 82
private let hGap:     CGFloat = 20   // horizontal gap between sibling subtrees
private let vGap:     CGFloat = 72   // vertical gap between levels
private let padSide:  CGFloat = 56
private let padVert:  CGFloat = 48

// MARK: - Tree Layout Engine

/// Recursive subtree width
private func subtreeW(_ id: String, nodes: [OrgNode]) -> CGFloat {
    let kids = nodes.filter { $0.reportsTo == id }
    guard !kids.isEmpty else { return cardW }
    let total = kids.reduce(CGFloat(0)) { $0 + subtreeW($1.id, nodes: nodes) }
    return total + CGFloat(kids.count - 1) * hGap
}

/// Computes center-point for every node using a Reingold-Tilford-style top-down pass.
private func computeLayout(nodes: [OrgNode]) -> [String: CGPoint] {
    var positions: [String: CGPoint] = [:]

    func layout(_ id: String, startX: CGFloat, level: Int) {
        let sw = subtreeW(id, nodes: nodes)
        positions[id] = CGPoint(
            x: startX + sw / 2,
            y: padVert + CGFloat(level) * (cardH + vGap) + cardH / 2
        )
        let kids = nodes.filter { $0.reportsTo == id }
                        .sorted { $0.role.priority < $1.role.priority }
        var x = startX
        for kid in kids {
            layout(kid.id, startX: x, level: level + 1)
            x += subtreeW(kid.id, nodes: nodes) + hGap
        }
    }

    let roots = nodes.filter { $0.reportsTo == nil }
                     .sorted { $0.role.priority < $1.role.priority }
    var x: CGFloat = padSide
    for root in roots {
        layout(root.id, startX: x, level: 0)
        x += subtreeW(root.id, nodes: nodes) + hGap
    }
    return positions
}

private func canvasSize(positions: [String: CGPoint]) -> CGSize {
    guard !positions.isEmpty else { return CGSize(width: 600, height: 400) }
    let maxX = (positions.values.map(\.x).max() ?? 0) + cardW / 2 + padSide
    let maxY = (positions.values.map(\.y).max() ?? 0) + cardH / 2 + padVert
    return CGSize(width: max(maxX, 600), height: max(maxY, 400))
}

// MARK: - Main View

struct OrgChartView: View {
    @Environment(OrgService.self)         private var orgService
    @Environment(FileWatcherService.self) private var watcher

    @State private var selectedNode:  OrgNode?
    @State private var showDetail     = true
    @State private var showAddSheet   = false
    @State private var addParentId:   String?
    @State private var watchToken:    WatchToken = -1

    private var layout: [String: CGPoint] { computeLayout(nodes: orgService.nodes) }
    private var size:   CGSize            { canvasSize(positions: layout) }

    var body: some View {
        HSplitView {
            treePanel
                .frame(minWidth: 420)
            if showDetail {
                NodeDetailPanel(
                    node: selectedNode,
                    orgService: orgService,
                    onSelect: { selectedNode = $0 },
                    onAddChild: { parentId in
                        addParentId = parentId
                        showAddSheet = true
                    }
                )
                .frame(minWidth: 260, maxWidth: 300)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addParentId = nil
                    showAddSheet = true
                } label: {
                    Label("Add Agent", systemImage: "plus.circle")
                }
                Divider()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDetail.toggle() }
                } label: {
                    Label("Detail Panel", systemImage: showDetail ? "sidebar.right" : "sidebar.right")
                }
                .help(showDetail ? "Hide Detail Panel" : "Show Detail Panel")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddOrgNodeSheet(orgService: orgService, defaultParentId: addParentId)
        }
        .onAppear {
            orgService.load()
            let orgDir = NSHomeDirectory() + "/.claude/orchestrator/org"
            watchToken = watcher.watch(orgDir) { [self] in
                orgService.load()
                if let sel = selectedNode {
                    selectedNode = orgService.node(id: sel.id)
                }
            }
        }
        .onDisappear { watcher.unwatch(watchToken) }
        .navigationTitle("Org Chart")
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        Group {
            if orgService.nodes.isEmpty {
                emptyState
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        // Connection lines drawn first (behind cards)
                        Canvas { ctx, _ in
                            drawConnections(ctx: ctx)
                        }
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)

                        // Team group backgrounds
                        teamGroupBackgrounds

                        // Agent cards
                        ForEach(orgService.nodes) { node in
                            if let pos = layout[node.id] {
                                OrgCardView(
                                    node: node,
                                    isSelected: selectedNode?.id == node.id
                                )
                                .frame(width: cardW, height: cardH)
                                .position(pos)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedNode = (selectedNode?.id == node.id) ? nil : node
                                    }
                                }
                                .contextMenu {
                                    cardContextMenu(node: node)
                                }
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No agents in the org chart yet")
                .foregroundStyle(.secondary)
            Button("Add First Agent") {
                addParentId = nil
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Team Group Backgrounds

    @ViewBuilder
    private var teamGroupBackgrounds: some View {
        let teams = Dictionary(grouping: orgService.nodes.filter { $0.team != nil }) { $0.team! }
        ForEach(Array(teams.keys.enumerated()), id: \.element) { idx, team in
            let teamNodes = teams[team] ?? []
            let positions = teamNodes.compactMap { layout[$0.id] }
            if positions.count > 1 {
                let minX = (positions.map(\.x).min() ?? 0) - cardW / 2 - 10
                let maxX = (positions.map(\.x).max() ?? 0) + cardW / 2 + 10
                let minY = (positions.map(\.y).min() ?? 0) - cardH / 2 - 8
                let maxY = (positions.map(\.y).max() ?? 0) + cardH / 2 + 8
                let teamColor = teamColor(for: idx)
                RoundedRectangle(cornerRadius: 14)
                    .fill(teamColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(teamColor.opacity(0.18), lineWidth: 1)
                    )
                    .frame(width: maxX - minX, height: maxY - minY)
                    .position(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
                    .allowsHitTesting(false)

                Text(team)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(teamColor.opacity(0.7))
                    .position(x: minX + 8 + (team.count > 0 ? CGFloat(team.count) * 3 : 0), y: minY + 12)
                    .allowsHitTesting(false)
            }
        }
    }

    private func teamColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .yellow, .teal]
        return colors[index % colors.count]
    }

    // MARK: - Connection Lines

    private func drawConnections(ctx: GraphicsContext) {
        for node in orgService.nodes {
            guard
                let parentId  = node.reportsTo,
                let parentPos = layout[parentId],
                let childPos  = layout[node.id]
            else { continue }

            let start = CGPoint(x: parentPos.x, y: parentPos.y + cardH / 2)
            let end   = CGPoint(x: childPos.x,  y: childPos.y  - cardH / 2)
            let midY  = start.y + vGap * 0.45

            var path = Path()
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x, y: midY))
            path.addLine(to: CGPoint(x: end.x,   y: midY))
            path.addLine(to: end)

            ctx.stroke(
                path,
                with: .color(.secondary.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cardContextMenu(node: OrgNode) -> some View {
        Button {
            addParentId = node.id
            showAddSheet = true
        } label: {
            Label("Add Direct Report", systemImage: "plus.circle")
        }
        Divider()
        Menu("Set Status") {
            ForEach(AgentOrgStatus.allCases, id: \.self) { s in
                Button(s.label) { orgService.setStatus(s, for: node.id) }
            }
        }
        Divider()
        Button(role: .destructive) {
            if selectedNode?.id == node.id { selectedNode = nil }
            orgService.removeNode(id: node.id)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}

// MARK: - Org Card View

struct OrgCardView: View {
    let node: OrgNode
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: isSelected ? roleColor.opacity(0.35) : .black.opacity(0.12),
                    radius: isSelected ? 8 : 4, x: 0, y: 2)
            .overlay(alignment: .leading) {
                // Role-colored accent bar
                RoundedRectangle(cornerRadius: 11)
                    .fill(roleColor)
                    .frame(width: 4)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 11,
                            bottomLeadingRadius: 11,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )
            }
            .overlay {
                HStack(spacing: 9) {
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(roleColor.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Text(node.avatarInitials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(roleColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        // Name + status dot
                        HStack(spacing: 5) {
                            Text(node.agentName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                        }
                        // Title / role
                        Text(node.title.isEmpty ? node.role.label : node.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Current task (if any)
                        if let task = node.currentTask, !task.isEmpty {
                            Text(task)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .italic()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isSelected ? roleColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
    }

    private var roleColor: Color {
        switch node.role {
        case .ceo:        return .purple
        case .teamLead:   return .blue
        case .engineer:   return .green
        case .specialist: return .orange
        }
    }

    private var statusColor: Color {
        switch node.status {
        case .active:  return .green
        case .idle:    return Color(nsColor: .systemYellow)
        case .paused:  return .orange
        case .offline: return Color(nsColor: .systemGray)
        }
    }
}

// MARK: - Node Detail Panel

struct NodeDetailPanel: View {
    let node: OrgNode?
    let orgService: OrgService
    let onSelect: (OrgNode?) -> Void
    let onAddChild: (String) -> Void

    @State private var editName   = ""
    @State private var editTitle  = ""
    @State private var editRole   = OrgRole.engineer
    @State private var editTeam   = ""
    @State private var editStatus = AgentOrgStatus.idle
    @State private var editTask   = ""
    @State private var editResp   = ""   // comma-separated
    @State private var editSkills = ""   // comma-separated
    @State private var isEditing  = false

    var body: some View {
        Group {
            if let node = node {
                detailContent(node: node)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Select an agent card\nto see details")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private func detailContent(node: OrgNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerSection(node: node)

                Divider()

                if isEditing {
                    editSection(node: node)
                } else {
                    infoSection(node: node)
                }

                Divider().padding(.top, 8)

                // Actions
                actionsSection(node: node)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: node.id) { _, _ in
            isEditing = false
            populateEdit(from: node)
        }
        .onAppear { populateEdit(from: node) }
    }

    private func headerSection(node: OrgNode) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(roleColor(node.role).opacity(0.2))
                    .frame(width: 60, height: 60)
                Text(node.avatarInitials)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(roleColor(node.role))
            }
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text(node.agentName)
                    .font(.headline)
                    .lineLimit(1)
                Text(node.title.isEmpty ? node.role.label : node.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(node.role.label, systemImage: node.role.icon)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(roleColor(node.role).opacity(0.15))
                        .foregroundStyle(roleColor(node.role))
                        .clipShape(Capsule())

                    Label(node.status.label, systemImage: "circle.fill")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusColor(node.status).opacity(0.12))
                        .foregroundStyle(statusColor(node.status))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private func infoSection(node: OrgNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let team = node.team, !team.isEmpty {
                infoRow(label: "Team", value: team, icon: "person.3")
            }
            if let parentId = node.reportsTo, let parent = orgService.node(id: parentId) {
                Button {
                    onSelect(parent)
                } label: {
                    HStack {
                        Label("Reports to", systemImage: "arrow.up.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(parent.agentName)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
            }
            if let task = node.currentTask, !task.isEmpty {
                infoRow(label: "Current Task", value: task, icon: "checklist")
            }
            if !node.responsibilities.isEmpty {
                detailListRow(label: "Responsibilities", items: node.responsibilities, icon: "list.bullet")
            }
            if !node.skills.isEmpty {
                detailListRow(label: "Skills", items: node.skills, icon: "bolt")
            }

            // Delegation chain
            let chain = orgService.chain(for: node.id)
            if chain.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Chain of Command", systemImage: "arrow.up.arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(chain.enumerated()), id: \.element.id) { idx, n in
                            HStack(spacing: 6) {
                                Text(String(repeating: "  ", count: idx) + (idx > 0 ? "↳ " : ""))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(n.agentName)
                                    .font(.caption)
                                    .fontWeight(n.id == node.id ? .semibold : .regular)
                                    .foregroundStyle(n.id == node.id ? .primary : .secondary)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
            }

            // Direct reports count
            let reportCount = orgService.children(of: node.id).count
            if reportCount > 0 {
                infoRow(label: "Direct Reports", value: "\(reportCount)", icon: "person.2")
            }
        }
        .padding(.vertical, 10)
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
    }

    private func detailListRow(label: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            FlowTagView(tags: items)
                .padding(.horizontal, 10)
        }
    }

    private func editSection(node: OrgNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                editField("Agent Name", text: $editName)
                editField("Title / Position", text: $editTitle)
                editField("Team", text: $editTeam)
                editField("Current Task", text: $editTask)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Role").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                    Picker("", selection: $editRole) {
                        ForEach(OrgRole.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Status").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                    Picker("", selection: $editStatus) {
                        ForEach(AgentOrgStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                }

                editField("Responsibilities (comma-separated)", text: $editResp)
                editField("Skills (comma-separated)", text: $editSkills)
            }

            HStack {
                Button("Cancel") { isEditing = false; populateEdit(from: node) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") { saveEdit(node: node) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .padding(.horizontal, 14)
        }
    }

    private func actionsSection(node: OrgNode) -> some View {
        VStack(spacing: 8) {
            Button {
                isEditing = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                onAddChild(node.id)
            } label: {
                Label("Add Direct Report", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onSelect(nil)
                orgService.removeNode(id: node.id)
            } label: {
                Label("Remove from Org Chart", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func populateEdit(from node: OrgNode) {
        editName   = node.agentName
        editTitle  = node.title
        editRole   = node.role
        editTeam   = node.team ?? ""
        editStatus = node.status
        editTask   = node.currentTask ?? ""
        editResp   = node.responsibilities.joined(separator: ", ")
        editSkills = node.skills.joined(separator: ", ")
    }

    private func saveEdit(node: OrgNode) {
        var updated = node
        updated.agentName       = editName.trimmingCharacters(in: .whitespaces)
        updated.title           = editTitle.trimmingCharacters(in: .whitespaces)
        updated.role            = editRole
        updated.team            = editTeam.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editTeam.trimmingCharacters(in: .whitespaces)
        updated.status          = editStatus
        updated.currentTask     = editTask.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editTask.trimmingCharacters(in: .whitespaces)
        updated.responsibilities = editResp.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        updated.skills           = editSkills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        orgService.updateNode(updated)
        isEditing = false
    }

    private func roleColor(_ role: OrgRole) -> Color {
        switch role {
        case .ceo:        return .purple
        case .teamLead:   return .blue
        case .engineer:   return .green
        case .specialist: return .orange
        }
    }

    private func statusColor(_ status: AgentOrgStatus) -> Color {
        switch status {
        case .active:  return .green
        case .idle:    return Color(nsColor: .systemYellow)
        case .paused:  return .orange
        case .offline: return .gray
        }
    }
}

// MARK: - Flow Tag View (for responsibilities/skills)

private struct FlowTagView: View {
    let tags: [String]

    var body: some View {
        var rows: [[String]] = [[]]
        for tag in tags {
            rows[rows.count - 1].append(tag)
            if rows[rows.count - 1].count >= 3 { rows.append([]) }
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Add Org Node Sheet

struct AddOrgNodeSheet: View {
    let orgService: OrgService
    let defaultParentId: String?

    @Environment(\.dismiss) private var dismiss

    @State private var agentName = ""
    @State private var role      = OrgRole.engineer
    @State private var title     = ""
    @State private var team      = ""
    @State private var reportsTo: String?
    @State private var skills    = ""
    @State private var resp      = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Add Agent to Org Chart", systemImage: "person.badge.plus")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                Section("Identity") {
                    TextField("Agent name (required)", text: $agentName)
                    TextField("Title / Position", text: $title)
                }
                Section("Role & Team") {
                    Picker("Role", selection: $role) {
                        ForEach(OrgRole.allCases, id: \.self) { r in
                            Label(r.label, systemImage: r.icon).tag(r)
                        }
                    }
                    TextField("Team (optional)", text: $team)
                }
                Section("Reports To") {
                    Picker("Reports to", selection: $reportsTo) {
                        Text("Nobody (Root)").tag(String?.none)
                        ForEach(orgService.nodes) { n in
                            Text("\(n.agentName) — \(n.role.label)").tag(String?.some(n.id))
                        }
                    }
                }
                Section("Skills & Responsibilities") {
                    TextField("Skills (comma-separated)", text: $skills)
                    TextField("Responsibilities (comma-separated)", text: $resp)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Add Agent") {
                    let name = agentName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    orgService.addNode(
                        agentName: name,
                        role: role,
                        title: title.trimmingCharacters(in: .whitespaces),
                        reportsTo: reportsTo,
                        team: team.isEmpty ? nil : team.trimmingCharacters(in: .whitespaces),
                        responsibilities: resp.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                        skills: skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 440, height: 520)
        .onAppear { reportsTo = defaultParentId }
    }
}
