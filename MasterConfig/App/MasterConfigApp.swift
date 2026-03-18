import SwiftUI

@main
struct MasterConfigApp: App {
    @State private var claudeService    = ClaudeService()
    @State private var repoService     = RepoService()
    @State private var prefsService    = PrefsService()
    @State private var fileWatcher     = FileWatcherService()
    @State private var terminalService      = TerminalService()
    @State private var orchestratorService  = OrchestratorService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(claudeService)
                .environment(repoService)
                .environment(prefsService)
                .environment(fileWatcher)
                .environment(terminalService)
                .environment(orchestratorService)
                .task {
                    // Wire up shared TerminalService for pane-based agent spawning
                    orchestratorService.terminalService = terminalService
                    await claudeService.loadAll()
                    await repoService.scanRepos()
                    terminalService.discoverOrphanSessions()
                    await orchestratorService.resumeTeam()
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
