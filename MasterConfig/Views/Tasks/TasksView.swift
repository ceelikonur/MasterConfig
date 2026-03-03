import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)

    static let statusGreen = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let statusBlue = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let statusGray = Color(red: 0.34, green: 0.37, blue: 0.54)
    static let statusRed = Color(red: 0.97, green: 0.47, blue: 0.56)
}

// MARK: - TasksView

struct TasksView: View {
    @Environment(FileWatcherService.self) private var fileWatcher
    @State private var teams: [TaskTeam] = []
    @State private var selectedTeam: TaskTeam?
    @State private var tasks: [TaskItem] = []
    @State private var watchToken: WatchToken?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var lastUpdated: Date = Date()
    @State private var isLive = true

    private let fm = FileManager.default
    private let teamsDir: String = {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/teams")
    }()
    private let tasksDir: String = {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/tasks")
    }()

    var body: some View {
        HSplitView {
            teamListPanel
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            teamDetailPanel
                .frame(minWidth: 400)
        }
        .background(Color.bgPrimary)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task {
            loadTeams()
        }
        .onDisappear {
            if let token = watchToken {
                fileWatcher.unwatch(token)
            }
        }
    }

    // MARK: - Left Panel

    private var teamListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Teams")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.statusGreen)
                        .frame(width: 8, height: 8)
                        .opacity(isLive ? 1 : 0.3)
                    Text("Live")
                        .font(.caption2)
                        .foregroundStyle(Color.statusGreen)
                    Text("· \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
                Button {
                    loadTeams()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .help("Refresh teams")
            }
            .padding(12)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .controlSize(.small)
                    .padding()
            }

            if teams.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.title)
                        .foregroundStyle(Color.textSecondary)
                    Text("No active teams")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(teams, id: \.id, selection: $selectedTeam) { team in
                    teamRow(team)
                        .tag(team)
                        .listRowBackground(
                            selectedTeam?.id == team.id
                                ? Color.accent.opacity(0.15)
                                : Color.clear
                        )
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedTeam) { _, newTeam in
                    if let team = newTeam {
                        loadTasks(for: team)
                        setupWatcher(for: team)
                    }
                }
            }
        }
        .background(Color.bgPrimary)
    }

    private func teamRow(_ team: TaskTeam) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(Color.accent)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text("\(team.members.count) member\(team.members.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Right Panel

    private var teamDetailPanel: some View {
        Group {
            if let team = selectedTeam {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        teamHeader(team)
                        membersSection(team)
                        tasksSection
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textSecondary)
                    Text("Select a team to view tasks")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgPrimary)
    }

    private func teamHeader(_ team: TaskTeam) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(team.name)
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            if !team.description.isEmpty {
                Text(team.description)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(spacing: 16) {
                Label("\(team.members.count) members", systemImage: "person.2")
                Label("\(tasks.count) tasks", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .cornerRadius(10)
    }

    private func membersSection(_ team: TaskTeam) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Members")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(team.members, id: \.name) { member in
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(Color.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Text(member.agentType)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accent.opacity(0.15))
                                .foregroundStyle(Color.accent)
                                .cornerRadius(3)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(Color.surface)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let inProgress = tasks.filter { $0.status == .inProgress }
            let pending = tasks.filter { $0.status == .pending }
            let completed = tasks.filter { $0.status == .completed }

            if !inProgress.isEmpty {
                taskGroup(title: "In Progress", tasks: inProgress, color: .statusBlue)
            }
            if !pending.isEmpty {
                taskGroup(title: "Pending", tasks: pending, color: .statusGray)
            }
            if !completed.isEmpty {
                taskGroup(title: "Completed", tasks: completed, color: .statusGreen)
            }

            if tasks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .foregroundStyle(Color.textSecondary)
                    Text("No tasks")
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(16)
            }
        }
    }

    private func taskGroup(title: String, tasks: [TaskItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            ForEach(tasks, id: \.id) { task in
                taskRow(task, color: color)
            }
        }
    }

    private func taskRow(_ task: TaskItem, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("#\(task.id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)

                Text(task.subject)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                Spacer()

                Text(task.status.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .cornerRadius(4)

                if let owner = task.owner, !owner.isEmpty {
                    Text(owner)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accent.opacity(0.15))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(4)
                }
            }

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            if !task.blockedBy.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.statusRed)
                    Text("Blocked by: \(task.blockedBy.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Color.statusRed)
                }
            }
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(8)
    }

    // MARK: - Data Loading

    private func loadTeams() {
        isLoading = true
        defer { isLoading = false }

        var result: [TaskTeam] = []
        let teamsURL = URL(fileURLWithPath: teamsDir)

        guard fm.fileExists(atPath: teamsDir),
              let contents = try? fm.contentsOfDirectory(at: teamsURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else {
            teams = []
            return
        }

        for dir in contents {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let configPath = dir.appendingPathComponent("config.json")
            guard fm.fileExists(atPath: configPath.path),
                  let data = try? Data(contentsOf: configPath),
                  let team = try? JSONDecoder().decode(TaskTeam.self, from: data)
            else { continue }

            result.append(team)
        }

        teams = result.sorted { $0.name < $1.name }
    }

    private func loadTasks(for team: TaskTeam) {
        let teamTasksDir = URL(fileURLWithPath: tasksDir).appendingPathComponent(team.name)
        guard fm.fileExists(atPath: teamTasksDir.path),
              let files = try? fm.contentsOfDirectory(at: teamTasksDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else {
            tasks = []
            return
        }

        var result: [TaskItem] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let task = try? JSONDecoder().decode(TaskItem.self, from: data)
            else { continue }
            if task.status != .deleted {
                result.append(task)
            }
        }

        tasks = result.sorted { $0.id < $1.id }
        lastUpdated = Date()
    }

    private func setupWatcher(for team: TaskTeam) {
        if let token = watchToken {
            fileWatcher.unwatch(token)
        }

        let teamTasksPath = (tasksDir as NSString).appendingPathComponent(team.name)
        watchToken = fileWatcher.watch(teamTasksPath) { [self] in
            if let currentTeam = selectedTeam {
                loadTasks(for: currentTeam)
            }
        }
    }
}

// MARK: - TaskTeam + Hashable

extension TaskTeam: Hashable {
    static func == (lhs: TaskTeam, rhs: TaskTeam) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension TeamMember: Hashable {
    static func == (lhs: TeamMember, rhs: TeamMember) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
