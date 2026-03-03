import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let purple = Color(red: 0.61, green: 0.55, blue: 0.98)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
}

// MARK: - PluginsView

struct PluginsView: View {
    @Environment(ClaudeService.self) private var claudeService
    @State private var searchText = ""
    @State private var selectedPlugin: Plugin?
    @State private var showingSkill: PluginSkill?
    @State private var activeFilter: PluginFilter = .all

    enum PluginFilter: String, CaseIterable {
        case all = "All"
        case official = "Official"
        case external = "External"
    }

    private var filteredPlugins: [Plugin] {
        var result = claudeService.plugins
        switch activeFilter {
        case .all: break
        case .official: result = result.filter { $0.isOfficial }
        case .external: result = result.filter { !$0.isOfficial }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.marketplaceName.lowercased().contains(q)
            }
        }
        return result
    }

    private func count(for filter: PluginFilter) -> Int {
        switch filter {
        case .all: return claudeService.plugins.count
        case .official: return claudeService.plugins.filter { $0.isOfficial }.count
        case .external: return claudeService.plugins.filter { !$0.isOfficial }.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().background(Color.textSecondary.opacity(0.3))

            if claudeService.plugins.isEmpty {
                emptyState
            } else {
                HSplitView {
                    pluginListPanel
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    detailPanel
                        .frame(minWidth: 400)
                }
            }
        }
        .background(Color.bgPrimary)
        .task {
            await claudeService.loadPlugins()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(PluginFilter.allCases, id: \.self) { filter in
                Button {
                    activeFilter = filter
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.rawValue)
                            .font(.system(.subheadline, weight: activeFilter == filter ? .semibold : .regular))
                        Text("\(count(for: filter))")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(activeFilter == filter ? Color.accent.opacity(0.3) : Color.textSecondary.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .foregroundStyle(activeFilter == filter ? Color.accent : Color.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(activeFilter == filter ? Color.accent.opacity(0.12) : Color.clear)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surface)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("No plugins found in ~/.claude/plugins/")
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Panel

    private var pluginListPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Filter plugins...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(10)
            .background(Color.surface)
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(filteredPlugins, id: \.id, selection: $selectedPlugin) { plugin in
                pluginRow(plugin)
                    .tag(plugin)
                    .listRowBackground(
                        selectedPlugin?.id == plugin.id
                            ? Color.accent.opacity(0.15)
                            : Color.clear
                    )
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedPlugin) { _, _ in
                showingSkill = nil
            }
        }
        .background(Color.bgPrimary)
    }

    private func pluginRow(_ plugin: Plugin) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(plugin.marketplaceName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Type badge
            Text(plugin.isOfficial ? "official" : "external")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((plugin.isOfficial ? Color.accent : Color.purple).opacity(0.15))
                .foregroundStyle(plugin.isOfficial ? Color.accent : Color.purple)
                .clipShape(Capsule())

            // Skill count badge
            if !plugin.skills.isEmpty {
                Text("\(plugin.skills.count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.textSecondary.opacity(0.2))
                    .foregroundStyle(Color.textSecondary)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Right Panel

    private var detailPanel: some View {
        Group {
            if let plugin = selectedPlugin {
                if let skill = showingSkill {
                    skillViewer(skill)
                } else {
                    pluginDetail(plugin)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textSecondary)
                    Text("Select a plugin")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Plugin Detail

    private func pluginDetail(_ plugin: Plugin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)

                    Text(plugin.isOfficial ? "official" : "external")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((plugin.isOfficial ? Color.accent : Color.purple).opacity(0.15))
                        .foregroundStyle(plugin.isOfficial ? Color.accent : Color.purple)
                        .clipShape(Capsule())
                }

                Text(plugin.marketplaceName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)

            Divider().background(Color.textSecondary.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // README
                    if !plugin.readme.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("README")
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)
                            Text(stripMarkdown(plugin.readme))
                                .font(.body)
                                .foregroundStyle(Color.textPrimary.opacity(0.85))
                                .textSelection(.enabled)
                        }
                    }

                    // Skills
                    if !plugin.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Skills (\(plugin.skills.count))")
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 10)
                            ], spacing: 10) {
                                ForEach(plugin.skills) { skill in
                                    Button {
                                        showingSkill = skill
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "doc.text")
                                                .font(.caption)
                                            Text(skill.name)
                                                .font(.system(.subheadline, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(Color.textPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.surface)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.textSecondary.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Skill Viewer

    private func skillViewer(_ skill: PluginSkill) -> some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Button {
                    showingSkill = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 16)

                Text(skill.name)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text("read-only")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.textSecondary.opacity(0.2))
                    .foregroundStyle(Color.textSecondary)
                    .cornerRadius(4)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.surface)

            Divider().background(Color.textSecondary.opacity(0.3))

            WebEditorView(
                content: .constant(skill.content),
                language: "markdown",
                isReadOnly: true
            )
        }
    }

    // MARK: - Helpers

    private func stripMarkdown(_ text: String) -> String {
        var result = text
        // Strip bold **text** and __text__
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#, with: "$1", options: .regularExpression)
        // Strip italic *text* and _text_
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(?<!\w)_(.+?)_(?!\w)"#, with: "$1", options: .regularExpression)
        return result
    }
}
