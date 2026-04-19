import SwiftUI

struct OverviewView: View {
    @Environment(ClaudeService.self)   private var claudeService
    @Environment(RepoService.self)     private var repoService
    @Environment(ActivityService.self) private var activityService

    var onNavigate: ((NavSection) -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private let statColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.11, blue: 0.15)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - Header
                    Text("Overview")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

                    // MARK: - Stat Cards
                    LazyVGrid(columns: statColumns, spacing: 16) {
                        StatCard(
                            title: "Skills",
                            count: claudeService.skills.count,
                            icon: "bolt.circle",
                            color: Color(red: 0.48, green: 0.64, blue: 0.97)
                        )
                        .onTapGesture { onNavigate?(.skills) }

                        StatCard(
                            title: "Agents",
                            count: claudeService.agents.count,
                            icon: "person.crop.circle",
                            color: Color(red: 0.62, green: 0.81, blue: 0.42)
                        )
                        .onTapGesture { onNavigate?(.agents) }

                        StatCard(
                            title: "MCP Servers",
                            count: claudeService.mcpServers.count,
                            icon: "server.rack",
                            color: Color(red: 1.0, green: 0.62, blue: 0.39)
                        )
                        .onTapGesture { onNavigate?(.mcp) }

                        StatCard(
                            title: "Repos",
                            count: repoService.repos.count,
                            icon: "folder.badge.gearshape",
                            color: Color(red: 0.61, green: 0.55, blue: 0.98)
                        )
                        .onTapGesture { onNavigate?(.repos) }
                    }

                    // MARK: - Recent Repos
                    Text("Recent Repos")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

                    if repoService.repos.isEmpty {
                        Text("No repos found. Hit Reload All to scan.")
                            .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(repoService.repos.prefix(6))) { repo in
                                RepoCard(repo: repo)
                            }
                        }
                    }

                    // MARK: - Recent Activity
                    Text("Recent Activity")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

                    ActivityFeedWidget(
                        entries: Array(activityService.entries.prefix(6)),
                        onViewAll: { onNavigate?(.activity) }
                    )
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                    // MARK: - Quick Actions
                    Text("Quick Actions")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await claudeService.loadAll()
                                await repoService.scanRepos()
                            }
                        } label: {
                            Label("Reload All", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.48, green: 0.64, blue: 0.97))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.claude"))
                        } label: {
                            Label("Open ~/.claude", systemImage: "folder")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(24)
            }

            // MARK: - Loading Overlay
            if claudeService.isLoading || repoService.isScanning {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: claudeService.isLoading)
        .animation(.easeInOut(duration: 0.15), value: repoService.isScanning)
        .task {
            await claudeService.loadMemoryFiles()
        }
    }

}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }

            Text("\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Repo Card

private struct RepoCard: View {
    let repo: Repo

    private var statusColor: Color {
        switch repo.status {
        case .clean:     return Color(red: 0.62, green: 0.81, blue: 0.42)
        case .modified:  return .yellow
        case .staged:    return .blue
        case .untracked: return Color(red: 1.0, green: 0.62, blue: 0.39)
        case .ahead:     return .cyan
        case .behind:    return Color(red: 0.61, green: 0.55, blue: 0.98)
        case .conflict:  return .red
        case .unknown:   return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + branch
            HStack(alignment: .center) {
                Text(repo.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                    .lineLimit(1)

                Spacer()

                Text(repo.branch)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.48, green: 0.64, blue: 0.97))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(repo.status.label)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
            }

            // Last commit
            if let commit = repo.lastCommit {
                Text(commit.message)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97).opacity(0.7))
                    .lineLimit(1)

                Text(commit.dateString)
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
            }

            // Path
            Text(repo.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}
