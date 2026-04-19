import Foundation
import AppKit

// MARK: - Import Export Service

@Observable
@MainActor
final class ImportExportService {

    // Published state
    var isExporting  = false
    var isImporting  = false
    var lastMessage: String?

    // Injected dependencies (wired in MasterConfigApp.task)
    var hierarchyService:  HierarchyService?
    var orgService:        OrgService?
    var budgetService:     BudgetService?
    var routineService:    RoutineService?
    var governanceService: GovernanceService?
    var claudeService:     ClaudeService?

    private let fm = FileManager.default

    // MARK: - Build Export Payload

    func buildExport(sections: Set<String>) -> MasterConfigExport {
        var s = ExportSections()
        if sections.contains("hierarchy") {
            s.goals      = hierarchyService?.goals
            s.projects   = hierarchyService?.projects
            s.milestones = hierarchyService?.milestones
            s.issues     = hierarchyService?.issues
        }
        if sections.contains("org")        { s.orgNodes  = orgService?.nodes }
        if sections.contains("budgets")    { s.budgets   = budgetService?.budgets }
        if sections.contains("routines")   { s.routines  = routineService?.routines }
        if sections.contains("governance") {
            s.governanceConfig = governanceService?.governanceConfig
            s.pendingApprovals = governanceService?.pendingApprovals
        }
        if sections.contains("skills") {
            s.skills = claudeService?.skills.map { SkillExport(name: $0.name, content: $0.content) }
        }
        if sections.contains("agents") {
            s.agents = claudeService?.agents.map { AgentExport(name: $0.name, content: $0.content, isGlobal: $0.isGlobal) }
        }
        if sections.contains("mcp") { s.mcpServers = claudeService?.mcpServers }
        return MasterConfigExport(exportDate: Date(), sections: s)
    }

    // MARK: - Export to File

    func exportToPanel(sections: Set<String>) {
        isExporting = true
        defer { isExporting = false }

        let export  = buildExport(sections: sections)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export) else {
            lastMessage = "Export encoding failed."
            return
        }

        let panel = NSSavePanel()
        panel.title                = "Export MasterConfig"
        panel.nameFieldStringValue = "masterconfig-\(dateStamp()).masterconfig"
        panel.canCreateDirectories = true
        panel.isExtensionHidden    = false
        panel.message              = "Save your MasterConfig configuration bundle."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            let n = countItems(sections: export.sections)
            lastMessage = "Exported \(n) items → \(url.lastPathComponent)"
        } catch {
            lastMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Import from File

    func openImportPanel() -> MasterConfigExport? {
        let panel = NSOpenPanel()
        panel.title                   = "Import MasterConfig"
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.message                 = "Select a .masterconfig bundle to import."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return parseExport(at: url)
    }

    func parseExport(at url: URL) -> MasterConfigExport? {
        guard let data = try? Data(contentsOf: url) else {
            lastMessage = "Could not read file."
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(MasterConfigExport.self, from: data) else {
            lastMessage = "Invalid or corrupted .masterconfig file."
            return nil
        }
        return export
    }

    // MARK: - Preview

    func preview(_ export: MasterConfigExport) -> ImportPreview {
        let s = export.sections
        var p = ImportPreview(
            version:        export.version,
            exportDate:     export.exportDate,
            appVersion:     export.appVersion,
            goalCount:      s.goals?.count            ?? 0,
            projectCount:   s.projects?.count         ?? 0,
            milestoneCount: s.milestones?.count       ?? 0,
            issueCount:     s.issues?.count           ?? 0,
            orgNodeCount:   s.orgNodes?.count         ?? 0,
            budgetCount:    s.budgets?.count          ?? 0,
            routineCount:   s.routines?.count         ?? 0,
            skillCount:     s.skills?.count           ?? 0,
            agentCount:     s.agents?.count           ?? 0,
            mcpServerCount: s.mcpServers?.count       ?? 0,
            approvalCount:  s.pendingApprovals?.count ?? 0
        )

        var conflicts: [ImportConflict] = []

        let existingGoals      = Set((hierarchyService?.goals     ?? []).map { $0.title })
        let existingProjects   = Set((hierarchyService?.projects  ?? []).map { $0.title })
        let existingIssues     = Set((hierarchyService?.issues    ?? []).map { $0.title })
        let existingRoutines   = Set((routineService?.routines    ?? []).map { $0.title })
        let existingOrgNames   = Set((orgService?.nodes           ?? []).map { $0.agentName })
        let existingSkills     = Set((claudeService?.skills       ?? []).map { $0.name })
        let existingAgents     = Set((claudeService?.agents       ?? []).map { $0.name })
        let existingMCPServers = Set((claudeService?.mcpServers   ?? []).map { $0.name })

        for g   in s.goals      ?? [] where existingGoals.contains(g.title)       { conflicts.append(ImportConflict(id: g.id,               section: "goals",    itemName: g.title)) }
        for pr  in s.projects   ?? [] where existingProjects.contains(pr.title)   { conflicts.append(ImportConflict(id: pr.id,              section: "projects", itemName: pr.title)) }
        for iss in s.issues     ?? [] where existingIssues.contains(iss.title)    { conflicts.append(ImportConflict(id: iss.id,             section: "issues",   itemName: iss.title)) }
        for r   in s.routines   ?? [] where existingRoutines.contains(r.title)    { conflicts.append(ImportConflict(id: r.id,               section: "routines", itemName: r.title)) }
        for n   in s.orgNodes   ?? [] where existingOrgNames.contains(n.agentName){ conflicts.append(ImportConflict(id: n.id,               section: "org",      itemName: n.agentName)) }
        for sk  in s.skills     ?? [] where existingSkills.contains(sk.name)      { conflicts.append(ImportConflict(id: "skill-\(sk.name)", section: "skills",   itemName: sk.name)) }
        for ag  in s.agents     ?? [] where existingAgents.contains(ag.name)      { conflicts.append(ImportConflict(id: "agent-\(ag.name)", section: "agents",   itemName: ag.name)) }
        for srv in s.mcpServers ?? [] where existingMCPServers.contains(srv.name) { conflicts.append(ImportConflict(id: "mcp-\(srv.name)",  section: "mcp",      itemName: srv.name)) }

        p.conflicts = conflicts
        return p
    }

    // MARK: - Apply Import

    func applyImport(export: MasterConfigExport, selectedSections: Set<String>, conflicts: [ImportConflict]) async {
        isImporting = true
        defer { isImporting = false }

        let s   = export.sections
        let res = Dictionary(uniqueKeysWithValues: conflicts.map { ($0.id, $0.resolution) })
        var imported = 0

        // ── Goals ────────────────────────────────────────────────────────────
        if selectedSections.contains("hierarchy"), let hs = hierarchyService {
            let existingGoalTitles = Set(hs.goals.map(\.title))
            for g in s.goals ?? [] {
                if !existingGoalTitles.contains(g.title) {
                    hs.createGoal(title: g.title, description: g.description)
                    imported += 1
                } else {
                    switch res[g.id] ?? .skip {
                    case .overwrite:
                        hs.updateGoal(g.id, title: g.title)
                        imported += 1
                    case .rename:
                        hs.createGoal(title: g.title + " (imported)", description: g.description)
                        imported += 1
                    case .skip:
                        break
                    }
                }
            }
            // Projects
            let existingProjectTitles = Set(hs.projects.map(\.title))
            for pr in s.projects ?? [] {
                if !existingProjectTitles.contains(pr.title) {
                    hs.createProject(title: pr.title, description: pr.description, goalId: nil)
                    imported += 1
                } else if res[pr.id] == .rename {
                    hs.createProject(title: pr.title + " (imported)", description: pr.description, goalId: nil)
                    imported += 1
                }
            }
        }

        // ── Org Chart ────────────────────────────────────────────────────────
        if selectedSections.contains("org"), let os = orgService {
            let existingNames = Set(os.nodes.map(\.agentName))
            for n in s.orgNodes ?? [] {
                if !existingNames.contains(n.agentName) {
                    os.addNode(agentName: n.agentName, role: n.role, title: n.title,
                               reportsTo: n.reportsTo, team: n.team,
                               responsibilities: n.responsibilities, skills: n.skills)
                    imported += 1
                } else if res[n.id] == .overwrite {
                    if let ex = os.nodes.first(where: { $0.agentName == n.agentName }) {
                        var u = ex; u.role = n.role; u.title = n.title; u.team = n.team
                        os.updateNode(u)
                        imported += 1
                    }
                }
            }
        }

        // ── Budgets ──────────────────────────────────────────────────────────
        if selectedSections.contains("budgets"), let bs = budgetService {
            for (agent, cfg) in s.budgets ?? [:] {
                bs.setBudget(agentName: agent, monthlyLimitUSD: cfg.monthlyLimitUSD,
                             softAlertThreshold: cfg.softAlertThreshold,
                             autoPauseEnabled: cfg.autoPauseEnabled)
                imported += 1
            }
        }

        // ── Routines ─────────────────────────────────────────────────────────
        if selectedSections.contains("routines"), let rs = routineService {
            let existingTitles = Set(rs.routines.map(\.title))
            for r in s.routines ?? [] {
                if !existingTitles.contains(r.title) {
                    rs.addRoutine(title: r.title, description: r.description,
                                  assignee: r.assignee, schedule: r.schedule,
                                  issueTemplate: r.issueTemplate)
                    imported += 1
                } else {
                    switch res[r.id] ?? .skip {
                    case .overwrite:
                        if let ex = rs.routines.first(where: { $0.title == r.title }) {
                            var u = ex; u.schedule = r.schedule; u.issueTemplate = r.issueTemplate
                            rs.updateRoutine(u)
                            imported += 1
                        }
                    case .rename:
                        rs.addRoutine(title: r.title + " (imported)", description: r.description,
                                      assignee: r.assignee, schedule: r.schedule,
                                      issueTemplate: r.issueTemplate)
                        imported += 1
                    case .skip:
                        break
                    }
                }
            }
        }

        // ── Milestones ───────────────────────────────────────────────────────
        if selectedSections.contains("hierarchy"), let hs = hierarchyService {
            let existingMilestoneTitles = Set(hs.milestones.map(\.title))
            for m in s.milestones ?? [] {
                if !existingMilestoneTitles.contains(m.title) {
                    hs.createMilestone(title: m.title, projectId: m.projectId, dueDate: m.dueDate)
                    imported += 1
                }
            }

            // ── Issues ───────────────────────────────────────────────────────
            let existingIssueTitles = Set(hs.issues.map(\.title))
            for issue in s.issues ?? [] {
                if !existingIssueTitles.contains(issue.title) {
                    hs.createIssue(
                        title:         issue.title,
                        description:   issue.description,
                        projectId:     issue.projectId,
                        milestoneId:   issue.milestoneId,
                        parentIssueId: issue.parentIssueId,
                        assignee:      issue.assignee,
                        priority:      issue.priority,
                        labels:        issue.labels
                    )
                    imported += 1
                } else if res[issue.id] == .overwrite {
                    hs.updateIssue(issue.id, title: issue.title, description: issue.description,
                                   status: issue.status, priority: issue.priority,
                                   assignee: issue.assignee, labels: issue.labels)
                    imported += 1
                }
            }
        }

        // ── Governance Config ─────────────────────────────────────────────────
        if selectedSections.contains("governance"), let gs = governanceService,
           let cfg = s.governanceConfig {
            // Apply each required approval type from the imported config
            for type_ in ApprovalType.allCases {
                let shouldBeRequired = cfg.requiredApprovalTypes.contains(type_.rawValue)
                gs.setApprovalRequired(type_, required: shouldBeRequired)
            }
            imported += 1
        }

        // ── MCP Servers ───────────────────────────────────────────────────────
        if selectedSections.contains("mcp"), let cs = claudeService {
            let existingServerNames = Set(cs.mcpServers.map(\.name))
            for srv in s.mcpServers ?? [] {
                if !existingServerNames.contains(srv.name) {
                    try? await cs.saveMCPServer(srv)
                    imported += 1
                } else if res["mcp-\(srv.name)"] == .overwrite {
                    try? await cs.saveMCPServer(srv)
                    imported += 1
                }
            }
        }

        // ── Skills ───────────────────────────────────────────────────────────
        if selectedSections.contains("skills"), let cs = claudeService {
            let existingNames = Set(cs.skills.map(\.name))
            for sk in s.skills ?? [] {
                if !existingNames.contains(sk.name) {
                    let skill = Skill(name: sk.name, description: "", content: sk.content,
                                      directoryPath: "", frontmatter: [:])
                    try? await cs.saveSkill(skill)
                    imported += 1
                } else if res["skill-\(sk.name)"] == .overwrite {
                    if let ex = cs.skills.first(where: { $0.name == sk.name }) {
                        var u = ex; u.content = sk.content
                        try? await cs.saveSkill(u)
                        imported += 1
                    }
                }
            }
        }

        // ── Agents ───────────────────────────────────────────────────────────
        if selectedSections.contains("agents"), let cs = claudeService {
            let existingNames = Set(cs.agents.map(\.name))
            for ag in s.agents ?? [] {
                if !existingNames.contains(ag.name) {
                    let agent = Agent(name: ag.name, description: "", model: "claude-sonnet-4-6",
                                      tools: [], content: ag.content, filePath: "", isGlobal: ag.isGlobal)
                    try? await cs.saveAgent(agent)
                    imported += 1
                } else if res["agent-\(ag.name)"] == .overwrite {
                    if let ex = cs.agents.first(where: { $0.name == ag.name }) {
                        var u = ex; u.content = ag.content
                        try? await cs.saveAgent(u)
                        imported += 1
                    }
                }
            }
        }

        lastMessage = imported > 0
            ? "Successfully imported \(imported) items."
            : "Nothing new to import (all items already exist or were skipped)."
    }

    // MARK: - Section List Builder (for UI)

    func currentSectionItems() -> [ExportSectionItem] {
        [
            ExportSectionItem(id: "hierarchy", label: "Goals, Projects & Issues",  icon: "checklist",               count: (hierarchyService?.goals.count ?? 0) + (hierarchyService?.issues.count ?? 0), isSelected: true),
            ExportSectionItem(id: "org",       label: "Org Chart",                 icon: "person.3",                count: orgService?.nodes.count          ?? 0, isSelected: true),
            ExportSectionItem(id: "budgets",   label: "Budget Configs",            icon: "dollarsign.circle",       count: budgetService?.budgets.count     ?? 0, isSelected: true),
            ExportSectionItem(id: "routines",  label: "Routines",                  icon: "repeat",                  count: routineService?.routines.count   ?? 0, isSelected: true),
            ExportSectionItem(id: "governance",label: "Governance Config",         icon: "shield",                  count: 1,                                     isSelected: true),
            ExportSectionItem(id: "skills",    label: "Skills",                    icon: "book.closed",             count: claudeService?.skills.count      ?? 0, isSelected: true),
            ExportSectionItem(id: "agents",    label: "Agent Definitions",         icon: "person.crop.rectangle",  count: claudeService?.agents.count      ?? 0, isSelected: true),
            ExportSectionItem(id: "mcp",       label: "MCP Servers",              icon: "server.rack",             count: claudeService?.mcpServers.count  ?? 0, isSelected: true),
        ]
    }

    // MARK: - Helpers

    private func dateStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func countItems(sections s: ExportSections) -> Int {
        var n = 0
        n += s.goals?.count            ?? 0
        n += s.projects?.count         ?? 0
        n += s.milestones?.count       ?? 0
        n += s.issues?.count           ?? 0
        n += s.orgNodes?.count         ?? 0
        n += s.budgets?.count          ?? 0
        n += s.routines?.count         ?? 0
        n += s.skills?.count           ?? 0
        n += s.agents?.count           ?? 0
        n += s.mcpServers?.count       ?? 0
        n += s.pendingApprovals?.count ?? 0
        return n
    }
}
