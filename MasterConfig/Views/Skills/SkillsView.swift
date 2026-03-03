import SwiftUI

struct SkillsView: View {
    @Environment(ClaudeService.self) private var claudeService
    @State private var selectedSkill: Skill?
    @State private var searchText = ""
    @State private var editorContent = ""
    @State private var showCreateSheet = false
    @State private var showDeleteAlert = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private enum SaveStatus {
        case idle, saving, saved
    }

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return claudeService.skills }
        let q = searchText.lowercased()
        return claudeService.skills.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            skillList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            detailPanel
                .frame(minWidth: 400)
        }
        .task { await claudeService.loadSkills() }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Delete Skill", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(selectedSkill?.name ?? "")\"? This cannot be undone.")
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSkillSheet { newSkill in
                createSkill(newSkill)
            }
        }
    }

    // MARK: - Skill List

    private var skillList: some View {
        VStack(spacing: 0) {
            searchField
            if filteredSkills.isEmpty {
                emptyListPlaceholder
            } else {
                List(filteredSkills, selection: $selectedSkill) { skill in
                    SkillRow(skill: skill)
                        .tag(skill)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.15))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
                Button {
                    if selectedSkill != nil { showDeleteAlert = true }
                } label: {
                    Label("Delete Skill", systemImage: "minus")
                }
                .disabled(selectedSkill == nil)
            }
        }
        .onChange(of: selectedSkill) { _, newValue in
            editorContent = newValue?.content ?? ""
            saveStatus = .idle
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            TextField("Filter skills...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
        }
        .padding(8)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    private var emptyListPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lightbulb")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            Text("No skills found")
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            if searchText.isEmpty {
                Text("Click + to create a new skill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let skill = selectedSkill {
                VStack(spacing: 0) {
                    WebEditorView(
                        content: $editorContent,
                        language: "markdown",
                        isReadOnly: false,
                        onSave: { saveCurrentSkill() }
                    )
                    statusBar(for: skill)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    Text("Select a skill to edit")
                        .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.1, green: 0.11, blue: 0.15))
            }
        }
    }

    private func statusBar(for skill: Skill) -> some View {
        HStack {
            Text(skill.directoryPath)
                .font(.caption)
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
            Button("Save") { saveCurrentSkill() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }

    // MARK: - Actions

    private func saveCurrentSkill() {
        guard var skill = selectedSkill else { return }
        skill.content = editorContent
        let fm = claudeService.parseFrontmatter(editorContent)
        skill.frontmatter = fm
        if let name = fm["name"], !name.isEmpty { skill.name = name }
        if let desc = fm["description"] { skill.description = desc }
        saveStatus = .saving
        Task {
            do {
                try await claudeService.saveSkill(skill)
                saveStatus = .saved
                // Re-select updated skill
                selectedSkill = claudeService.skills.first { $0.name == skill.name }
            } catch {
                saveStatus = .idle
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func deleteSelected() {
        guard let skill = selectedSkill else { return }
        Task {
            do {
                try await claudeService.deleteSkill(skill)
                selectedSkill = nil
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func createSkill(_ skill: Skill) {
        Task {
            do {
                try await claudeService.saveSkill(skill)
                selectedSkill = claudeService.skills.first { $0.name == skill.name }
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Skill Sheet

private struct CreateSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    let onCreate: (Skill) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("New Skill")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("my-skill", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
                TextField("What does this skill do?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let template = """
                    ---
                    name: \(name)
                    description: "\(description)"
                    ---

                    # \(name)

                    """
                    let skill = Skill(
                        name: name,
                        description: description,
                        content: template,
                        directoryPath: "",
                        frontmatter: ["name": name, "description": description]
                    )
                    onCreate(skill)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.64, blue: 0.97))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(red: 0.13, green: 0.14, blue: 0.18))
    }
}
