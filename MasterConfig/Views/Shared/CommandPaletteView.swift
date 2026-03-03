import SwiftUI

struct CommandPaletteView: View {
    @Binding var isVisible: Bool
    @Binding var selection: NavSection?

    @Environment(ClaudeService.self) private var claudeService
    @Environment(RepoService.self) private var repoService

    @State private var query = ""
    @State private var selectedIndex = 0

    private var commands: [PaletteCommand] {
        var result: [PaletteCommand] = []

        // Navigation commands
        for section in NavSection.allCases {
            result.append(PaletteCommand(
                title: section.rawValue,
                subtitle: "Navigate",
                icon: section.icon,
                section: section,
                action: {}
            ))
        }

        // Action commands
        result.append(PaletteCommand(
            title: "Reload All",
            subtitle: "Action",
            icon: "arrow.clockwise",
            action: { @Sendable in }
        ))
        result.append(PaletteCommand(
            title: "Open ~/.claude",
            subtitle: "Action",
            icon: "folder",
            action: { @Sendable in }
        ))

        // Skills
        for skill in claudeService.skills {
            result.append(PaletteCommand(
                title: "Open Skill: \(skill.name)",
                subtitle: skill.description,
                icon: "bolt.circle",
                section: .skills,
                action: { @Sendable in }
            ))
        }

        // Agents
        for agent in claudeService.agents {
            result.append(PaletteCommand(
                title: "Open Agent: \(agent.name)",
                subtitle: agent.description,
                icon: "person.crop.circle.badge.checkmark",
                section: .agents,
                action: { @Sendable in }
            ))
        }

        return result
    }

    private var filteredCommands: [PaletteCommand] {
        if query.isEmpty { return commands }
        let q = query.lowercased()
        return commands.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    private var navigationCommands: [PaletteCommand] {
        filteredCommands.filter { $0.section != nil && !$0.title.hasPrefix("Open Skill:") && !$0.title.hasPrefix("Open Agent:") }
    }

    private var actionCommands: [PaletteCommand] {
        filteredCommands.filter { $0.section == nil }
    }

    private var skillAgentCommands: [PaletteCommand] {
        filteredCommands.filter { $0.title.hasPrefix("Open Skill:") || $0.title.hasPrefix("Open Agent:") }
    }

    private var allDisplayed: [PaletteCommand] {
        navigationCommands + actionCommands + skillAgentCommands
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isVisible = false }

            VStack(spacing: 0) {
                // MARK: - Search Field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
                        .font(.system(size: 16))

                    TextField("Type a command...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .background(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.3))

                // MARK: - Results List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !navigationCommands.isEmpty {
                                sectionHeader("Navigation")
                                ForEach(Array(navigationCommands.enumerated()), id: \.element.id) { idx, cmd in
                                    commandRow(cmd, isSelected: globalIndex(for: cmd) == selectedIndex)
                                        .id(cmd.id)
                                        .onTapGesture { executeCommand(cmd) }
                                }
                            }

                            if !actionCommands.isEmpty {
                                sectionHeader("Actions")
                                ForEach(Array(actionCommands.enumerated()), id: \.element.id) { idx, cmd in
                                    commandRow(cmd, isSelected: globalIndex(for: cmd) == selectedIndex)
                                        .id(cmd.id)
                                        .onTapGesture { executeCommand(cmd) }
                                }
                            }

                            if !skillAgentCommands.isEmpty {
                                sectionHeader("Skills & Agents")
                                ForEach(Array(skillAgentCommands.enumerated()), id: \.element.id) { idx, cmd in
                                    commandRow(cmd, isSelected: globalIndex(for: cmd) == selectedIndex)
                                        .id(cmd.id)
                                        .onTapGesture { executeCommand(cmd) }
                                }
                            }

                            if allDisplayed.isEmpty {
                                Text("No matching commands")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if newValue < allDisplayed.count {
                            proxy.scrollTo(allDisplayed[newValue].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 560, height: 420)
            .background(.ultraThinMaterial)
            .background(Color(red: 0.1, green: 0.11, blue: 0.15).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .onKeyPress(.upArrow) {
                if selectedIndex > 0 { selectedIndex -= 1 }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if selectedIndex < allDisplayed.count - 1 { selectedIndex += 1 }
                return .handled
            }
            .onKeyPress(.return) {
                if selectedIndex < allDisplayed.count {
                    executeCommand(allDisplayed[selectedIndex])
                }
                return .handled
            }
            .onKeyPress(.escape) {
                isVisible = false
                return .handled
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .animation(.easeInOut(duration: 0.15), value: isVisible)
        .animation(.easeInOut(duration: 0.15), value: selectedIndex)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.34, green: 0.37, blue: 0.55))
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func commandRow(_ cmd: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: cmd.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : Color(red: 0.48, green: 0.64, blue: 0.97))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(cmd.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color(red: 0.75, green: 0.80, blue: 0.97))

                if !cmd.subtitle.isEmpty {
                    Text(cmd.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : Color(red: 0.34, green: 0.37, blue: 0.55))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.3)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func globalIndex(for cmd: PaletteCommand) -> Int {
        allDisplayed.firstIndex(of: cmd) ?? -1
    }

    private func executeCommand(_ cmd: PaletteCommand) {
        if let section = cmd.section {
            selection = section
        } else if cmd.title == "Reload All" {
            Task {
                await claudeService.loadAll()
                await repoService.scanRepos()
            }
        } else if cmd.title == "Open ~/.claude" {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.claude"))
        }
        isVisible = false
    }
}
