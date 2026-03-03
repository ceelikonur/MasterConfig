import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavSection?
    @Environment(ClaudeService.self) private var claudeService

    var body: some View {
        List(NavSection.allCases, selection: $selection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Master Config")
        .toolbar {
            ToolbarItem {
                if claudeService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
}
