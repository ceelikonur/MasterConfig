import SwiftUI
import Combine

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
}

// MARK: - SearchView

struct SearchView: View {
    @Environment(ClaudeService.self) private var claudeService
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var selectedResult: SearchResult?
    @State private var previewContent = ""
    @State private var isSearchFieldFocused = true
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var onNavigate: ((NavSection) -> Void)? = nil

    private var groupedResults: [(NavSection, [SearchResult])] {
        let grouped = Dictionary(grouping: results) { $0.section }
        let order: [NavSection] = [.skills, .agents, .memory, .repos, .mcp, .settings]
        return order.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().background(Color.textSecondary.opacity(0.3))

            if searchText.isEmpty {
                emptyState
            } else if results.isEmpty {
                noResultsState
            } else {
                HSplitView {
                    resultsList
                        .frame(minWidth: 300, idealWidth: 380)
                    previewPanel
                        .frame(minWidth: 300)
                }
            }
        }
        .background(Color.bgPrimary)
        .onAppear {
            fieldFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.accent)

            TextField("Search across skills, agents, and memory files...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(Color.textPrimary)
                .focused($fieldFocused)
                .onChange(of: searchText) { _, newValue in
                    debounceSearch(newValue)
                }
                .onSubmit {
                    if let result = selectedResult {
                        onNavigate?(result.section)
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
                    selectedResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.surface)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("Type to search across skills, agents, and memory files")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                searchHint(icon: "bolt.circle", label: "Skills")
                searchHint(icon: "person.crop.circle", label: "Agents")
                searchHint(icon: "brain", label: "Memory")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchHint(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(Color.textSecondary.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.surface)
        .cornerRadius(6)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.textSecondary)
            Text("No results for \"\(searchText)\"")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedResult) {
                ForEach(groupedResults, id: \.0) { section, items in
                    Section {
                        ForEach(items) { result in
                            resultRow(result)
                                .tag(result)
                                .id(result.id)
                                .listRowBackground(
                                    selectedResult?.id == result.id
                                        ? Color.accent.opacity(0.15)
                                        : Color.clear
                                )
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                                .font(.caption)
                            Text(section.rawValue)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedResult) { _, newResult in
                if let result = newResult {
                    loadPreview(for: result)
                    withAnimation {
                        proxy.scrollTo(result.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForSection(result.section))
                .foregroundStyle(Color.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)

                if !result.content.isEmpty {
                    Text(String(result.content.prefix(80)))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        Group {
            if let result = selectedResult {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: iconForSection(result.section))
                            .foregroundStyle(Color.accent)
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(result.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)

                        Button {
                            onNavigate?(result.section)
                        } label: {
                            Label("Go to", systemImage: "arrow.right.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Color.surface)

                    WebEditorView(
                        content: .constant(previewContent),
                        language: languageForSection(result.section),
                        isReadOnly: true
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title)
                        .foregroundStyle(Color.textSecondary)
                    Text("Select a result to preview")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Helpers

    private func debounceSearch(_ query: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = claudeService.search(query: query)
            if selectedResult == nil || !results.contains(where: { $0.id == selectedResult?.id }) {
                selectedResult = results.first
            }
        }
    }

    private func loadPreview(for result: SearchResult) {
        let path = result.filePath
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            previewContent = content
        } else {
            previewContent = result.content
        }
    }

    private func iconForSection(_ section: NavSection) -> String {
        switch section {
        case .skills:  return "bolt.circle.fill"
        case .agents:  return "person.crop.circle.badge.checkmark"
        case .memory:  return "brain"
        default:       return section.icon
        }
    }

    private func languageForSection(_ section: NavSection) -> String {
        switch section {
        case .skills:   return "markdown"
        case .agents:   return "markdown"
        case .memory:   return "markdown"
        case .settings: return "json"
        case .mcp:      return "json"
        default:        return "markdown"
        }
    }
}
