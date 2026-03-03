import SwiftUI

struct MemoryView: View {
    @Environment(ClaudeService.self) private var claudeService
    @State private var selectedTab: MemoryTab = .global
    @State private var globalContent = ""
    @State private var selectedProjectFile: MemoryFile?
    @State private var projectEditorContent = ""
    @State private var saveStatus: SaveStatus = .idle
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private enum MemoryTab: String, CaseIterable {
        case global = "Global"
        case projects = "Projects"
    }

    private enum SaveStatus {
        case idle, saving, saved
    }

    private var globalFile: MemoryFile? {
        claudeService.memoryFiles.first { $0.isGlobal }
    }

    private var projectFiles: [MemoryFile] {
        claudeService.memoryFiles.filter { !$0.isGlobal }
    }

    private var projectGroups: [(slug: String, files: [MemoryFile])] {
        let grouped = Dictionary(grouping: projectFiles) { $0.projectSlug ?? "unknown" }
        return grouped.sorted { $0.key < $1.key }.map { (slug: $0.key, files: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
            switch selectedTab {
            case .global:
                globalPanel
            case .projects:
                projectsPanel
            }
        }
        .task {
            await claudeService.loadMemoryFiles()
            globalContent = globalFile?.content ?? ""
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(MemoryTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    saveStatus = .idle
                } label: {
                    Text(tab.rawValue)
                        .font(.system(.body, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab
                            ? Color(red: 0.75, green: 0.80, blue: 0.97)
                            : Color(red: 0.34, green: 0.37, blue: 0.55))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color(red: 0.48, green: 0.64, blue: 0.97).opacity(0.15)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Global Panel

    private var globalPanel: some View {
        VStack(spacing: 0) {
            if globalFile != nil {
                WebEditorView(
                    content: $globalContent,
                    language: "markdown",
                    isReadOnly: false,
                    onSave: { saveGlobal() }
                )
                globalStatusBar
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("No global CLAUDE.md found")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("~/.claude/CLAUDE.md")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.1, green: 0.11, blue: 0.15))
            }
        }
    }

    private var globalStatusBar: some View {
        HStack {
            if let file = globalFile {
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            lineCharCount(for: globalContent)
            saveStatusIndicator
            Button("Save") { saveGlobal() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Projects Panel

    private var projectsPanel: some View {
        HSplitView {
            projectList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            projectDetail
                .frame(minWidth: 400)
        }
    }

    private var projectList: some View {
        VStack(spacing: 0) {
            if projectGroups.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("No project memory files")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedProjectFile) {
                    ForEach(projectGroups, id: \.slug) { group in
                        Section {
                            ForEach(group.files) { file in
                                ProjectFileRow(file: file)
                                    .tag(file)
                            }
                        } header: {
                            Text(group.slug)
                                .font(.caption.bold())
                                .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .onChange(of: selectedProjectFile) { _, newValue in
            projectEditorContent = newValue?.content ?? ""
            saveStatus = .idle
        }
    }

    private var projectDetail: some View {
        Group {
            if let file = selectedProjectFile {
                VStack(spacing: 0) {
                    WebEditorView(
                        content: $projectEditorContent,
                        language: "markdown",
                        isReadOnly: false,
                        onSave: { saveProjectFile() }
                    )
                    projectStatusBar(for: file)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("Select a memory file to edit")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.1, green: 0.11, blue: 0.15))
            }
        }
    }

    private func projectStatusBar(for file: MemoryFile) -> some View {
        HStack {
            Text(file.path)
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            lineCharCount(for: projectEditorContent)
            saveStatusIndicator
            Button("Save") { saveProjectFile() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var saveStatusIndicator: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .controlSize(.small)
            Text("Saving...")
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Saved")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func lineCharCount(for content: String) -> some View {
        let lines = content.components(separatedBy: .newlines).count
        let chars = content.count
        return Text("\(lines) lines, \(chars) chars")
            .font(.caption)
            .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
    }

    // MARK: - Actions

    private func saveGlobal() {
        guard var file = globalFile else { return }
        file.content = globalContent
        saveStatus = .saving
        Task {
            do {
                try await claudeService.saveMemoryFile(file)
                saveStatus = .saved
            } catch {
                saveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func saveProjectFile() {
        guard var file = selectedProjectFile else { return }
        file.content = projectEditorContent
        saveStatus = .saving
        Task {
            do {
                try await claudeService.saveMemoryFile(file)
                saveStatus = .saved
                selectedProjectFile = claudeService.memoryFiles.first { $0.path == file.path }
            } catch {
                saveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Project File Row

private struct ProjectFileRow: View {
    let file: MemoryFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.displayName.components(separatedBy: "/").last ?? file.displayName)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
            Text("\(file.content.components(separatedBy: .newlines).count) lines")
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
        }
        .padding(.vertical, 2)
    }
}
