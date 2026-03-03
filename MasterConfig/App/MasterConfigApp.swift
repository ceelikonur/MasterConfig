import SwiftUI

@main
struct MasterConfigApp: App {
    @State private var claudeService    = ClaudeService()
    @State private var repoService     = RepoService()
    @State private var prefsService    = PrefsService()
    @State private var fileWatcher     = FileWatcherService()
    @State private var terminalService = TerminalService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(claudeService)
                .environment(repoService)
                .environment(prefsService)
                .environment(fileWatcher)
                .environment(terminalService)
                .task {
                    await claudeService.loadAll()
                    await repoService.scanRepos()
                    terminalService.discoverOrphanSessions()
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
