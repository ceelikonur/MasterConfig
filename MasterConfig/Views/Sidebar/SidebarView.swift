import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavSection?
    @Environment(ClaudeService.self)    private var claudeService
    @Environment(GovernanceService.self) private var governance

    var body: some View {
        List(NavSection.allCases, selection: $selection) { section in
            sidebarLabel(for: section)
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

    @ViewBuilder
    private func sidebarLabel(for section: NavSection) -> some View {
        if section == .approvals && governance.pendingCount > 0 {
            HStack {
                Label(section.rawValue, systemImage: section.icon)
                Spacer()
                Text("\(governance.pendingCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        } else {
            Label(section.rawValue, systemImage: section.icon)
        }
    }
}
