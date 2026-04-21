import SwiftUI

struct ContentView: View {
    @Environment(ClaudeService.self) private var claudeService
    @Environment(RepoService.self) private var repoService
    @Environment(PrefsService.self) private var prefsService
    @Environment(TerminalService.self) private var terminalService
    @Environment(OrchestratorService.self) private var orchestratorService
    @Environment(FleetService.self) private var fleetService

    @State private var selection: NavSection? = .overview
    @State private var showCommandPalette = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            detailView(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .center) {
            if showCommandPalette {
                CommandPaletteView(isVisible: $showCommandPalette, selection: $selection)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onKeyPress(.init("k"), phases: .down) { event in
            if event.modifiers.contains(.command) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCommandPalette.toggle()
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("f"), phases: .down) { event in
            if event.modifiers.contains([.command, .shift]) {
                selection = .search
                return .handled
            }
            return .ignored
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func detailView(for section: NavSection?) -> some View {
        switch section {
        case .overview, .none:
            OverviewView(onNavigate: { section in
                selection = section
            })
        case .repos:
            ReposView()
        case .skills:
            SkillsView()
        case .agents:
            AgentsView()
        case .plugins:
            PluginsView()
        case .mcp:
            McpView()
        case .memory:
            MemoryView()
        case .settings:
            SettingsView()
        case .tasks:
            TasksView()
        case .search:
            SearchView(onNavigate: { section in
                selection = section
            })
        case .visualize:
            VisualizeView()
        case .chat:
            ChatView()
        case .orchestrator:
            OrchestratorView()
        case .fleet:
            FleetView()
        case .costs:
            CostsView()
        case .approvals:
            ApprovalsView()
        case .orgChart:
            OrgChartView()
        case .routines:
            RoutinesView()
        case .activity:
            ActivityView()
        }
    }
}
