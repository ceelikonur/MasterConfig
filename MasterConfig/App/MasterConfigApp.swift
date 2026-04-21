import SwiftUI

@main
struct MasterConfigApp: App {
    @State private var claudeService        = ClaudeService()
    @State private var repoService          = RepoService()
    @State private var prefsService         = PrefsService()
    @State private var fileWatcher          = FileWatcherService()
    @State private var terminalService      = TerminalService()
    @State private var orchestratorService  = OrchestratorService()
    @State private var hierarchyService     = HierarchyService()
    @State private var budgetService        = BudgetService()
    @State private var governanceService    = GovernanceService()
    @State private var orgService           = OrgService()
    @State private var routineService       = RoutineService()
    @State private var activityService      = ActivityService()
    @State private var importExportService  = ImportExportService()
    @State private var fleetService         = FleetService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(claudeService)
                .environment(repoService)
                .environment(prefsService)
                .environment(fileWatcher)
                .environment(terminalService)
                .environment(orchestratorService)
                .environment(hierarchyService)
                .environment(budgetService)
                .environment(governanceService)
                .environment(orgService)
                .environment(routineService)
                .environment(activityService)
                .environment(importExportService)
                .environment(fleetService)
                .task {
                    // Wire up shared TerminalService for pane-based agent spawning
                    orchestratorService.terminalService = terminalService
                    // Wire RoutineService → HierarchyService so routines can create issues
                    routineService.hierarchyService   = hierarchyService
                    routineService.activityService    = activityService
                    governanceService.activityService = activityService
                    // Wire ImportExportService dependencies
                    importExportService.hierarchyService  = hierarchyService
                    importExportService.orgService        = orgService
                    importExportService.budgetService     = budgetService
                    importExportService.routineService    = routineService
                    importExportService.governanceService = governanceService
                    importExportService.claudeService     = claudeService
                    activityService.load()
                    await claudeService.loadAll()
                    await repoService.scanRepos()
                    terminalService.discoverOrphanSessions()
                    await orchestratorService.resumeTeam()
                    governanceService.requestNotificationPermission()
                    routineService.load()
                    routineService.startTimer()
                    fleetService.load()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Navigate") {
                ForEach(NavSection.allCases) { section in
                    Button(section.rawValue) { }
                        .keyboardShortcut(.none)
                }
            }
        }
    }
}
