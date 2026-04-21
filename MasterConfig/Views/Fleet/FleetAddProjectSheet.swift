import SwiftUI

// MARK: - Add Project Sheet

struct FleetAddProjectSheet: View {
    @Environment(FleetService.self) private var fleetService
    @Environment(\.dismiss) private var dismiss

    let editingProject: FleetProject?

    @State private var name: String
    @State private var clientName: String
    @State private var notes: String

    @State private var githubEnabled: Bool
    @State private var ghOwner: String
    @State private var ghRepo: String
    @State private var ghBranch: String
    @State private var ghToken: String = ""

    @State private var supabaseEnabled: Bool
    @State private var sbProjectRef: String
    @State private var sbRegion: String
    @State private var sbToken: String = ""

    @State private var netlifyEnabled: Bool
    @State private var nfSiteId: String
    @State private var nfSiteName: String
    @State private var nfToken: String = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(editingProject: FleetProject? = nil) {
        self.editingProject = editingProject
        _name       = State(initialValue: editingProject?.name ?? "")
        _clientName = State(initialValue: editingProject?.clientName ?? "")
        _notes      = State(initialValue: editingProject?.notes ?? "")

        _githubEnabled = State(initialValue: editingProject?.github != nil)
        _ghOwner       = State(initialValue: editingProject?.github?.owner ?? "")
        _ghRepo        = State(initialValue: editingProject?.github?.repo ?? "")
        _ghBranch      = State(initialValue: editingProject?.github?.defaultBranch ?? "")

        _supabaseEnabled = State(initialValue: editingProject?.supabase != nil)
        _sbProjectRef    = State(initialValue: editingProject?.supabase?.projectRef ?? "")
        _sbRegion        = State(initialValue: editingProject?.supabase?.region ?? "")

        _netlifyEnabled = State(initialValue: editingProject?.netlify != nil)
        _nfSiteId       = State(initialValue: editingProject?.netlify?.siteId ?? "")
        _nfSiteName     = State(initialValue: editingProject?.netlify?.siteName ?? "")
    }

    // MARK: - Derived state

    private var isEditing: Bool { editingProject != nil }
    private var githubWasConfigured: Bool   { editingProject?.github   != nil }
    private var supabaseWasConfigured: Bool { editingProject?.supabase != nil }
    private var netlifyWasConfigured: Bool  { editingProject?.netlify  != nil }

    // MARK: - Validation

    // Token is required when adding OR when enabling an integration that wasn't previously configured.
    // In edit mode, if the integration was already configured, token can stay blank to keep existing.

    private var isGithubValid: Bool {
        guard githubEnabled else { return false }
        let ownerOk = !ghOwner.trimmingCharacters(in: .whitespaces).isEmpty
        let repoOk  = !ghRepo.trimmingCharacters(in: .whitespaces).isEmpty
        let tokenOk = !ghToken.isEmpty || (isEditing && githubWasConfigured)
        return ownerOk && repoOk && tokenOk
    }

    private var isSupabaseValid: Bool {
        guard supabaseEnabled else { return false }
        let refOk   = !sbProjectRef.trimmingCharacters(in: .whitespaces).isEmpty
        let tokenOk = !sbToken.isEmpty || (isEditing && supabaseWasConfigured)
        return refOk && tokenOk
    }

    private var isNetlifyValid: Bool {
        guard netlifyEnabled else { return false }
        let idOk    = !nfSiteId.trimmingCharacters(in: .whitespaces).isEmpty
        let tokenOk = !nfToken.isEmpty || (isEditing && netlifyWasConfigured)
        return idOk && tokenOk
    }

    private var canSubmit: Bool {
        let nameOk = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let anyIntegration = isGithubValid || isSupabaseValid || isNetlifyValid
        let noneDisabled   = githubEnabled  || supabaseEnabled || netlifyEnabled
        // in edit mode, allow saving even if user turned ALL integrations off (just removes refs)
        return nameOk && (anyIntegration || (isEditing && !noneDisabled)) && !isSubmitting
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                Section("Project") {
                    TextField("Project name (required)", text: $name)
                    TextField("Client label (optional)", text: $clientName)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Toggle("Enable GitHub", isOn: $githubEnabled.animation(.easeInOut(duration: 0.15)))
                    if githubEnabled {
                        TextField("Owner (e.g. anthropic)", text: $ghOwner)
                        TextField("Repo", text: $ghRepo)
                        TextField("Default branch (optional)", text: $ghBranch, prompt: Text("main"))
                        SecureField(tokenPrompt(wasConfigured: githubWasConfigured), text: $ghToken)
                    }
                } header: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Section {
                    Toggle("Enable Supabase", isOn: $supabaseEnabled.animation(.easeInOut(duration: 0.15)))
                    if supabaseEnabled {
                        TextField("Project ref", text: $sbProjectRef)
                        TextField("Region (optional)", text: $sbRegion)
                        SecureField(tokenPrompt(wasConfigured: supabaseWasConfigured, label: "Management API PAT"), text: $sbToken)
                    }
                } header: {
                    Label("Supabase", systemImage: "cylinder.split.1x2")
                }

                Section {
                    Toggle("Enable Netlify", isOn: $netlifyEnabled.animation(.easeInOut(duration: 0.15)))
                    if netlifyEnabled {
                        TextField("Site ID", text: $nfSiteId)
                        TextField("Site name (optional)", text: $nfSiteName)
                        SecureField(tokenPrompt(wasConfigured: netlifyWasConfigured), text: $nfToken)
                    }
                } header: {
                    Label("Netlify", systemImage: "globe")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 520, height: 640)
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack {
            Label(isEditing ? "Edit Fleet Project" : "Add Fleet Project",
                  systemImage: "shippingbox.and.arrow.backward")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape)
                .disabled(isSubmitting)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await submit() }
            } label: {
                Text(isEditing ? "Save" : "Add Project")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    private func tokenPrompt(wasConfigured: Bool, label: String = "Personal Access Token") -> String {
        if isEditing && wasConfigured {
            return "Leave blank to keep existing token"
        }
        return label
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let projectID = editingProject?.id ?? UUID().uuidString
        let keychain = KeychainService.shared

        var githubRef: GitHubRef?
        var supabaseRef: SupabaseRef?
        var netlifyRef: NetlifyRef?

        do {
            if githubEnabled && isGithubValid {
                let key = editingProject?.github?.tokenKeychainKey ?? "github_\(projectID)"
                if !ghToken.isEmpty {
                    try await keychain.setToken(ghToken, forKey: key)
                }
                let branchTrim = ghBranch.trimmingCharacters(in: .whitespaces)
                githubRef = GitHubRef(
                    owner: ghOwner.trimmingCharacters(in: .whitespaces),
                    repo: ghRepo.trimmingCharacters(in: .whitespaces),
                    defaultBranch: branchTrim.isEmpty ? nil : branchTrim,
                    tokenKeychainKey: key
                )
            }

            if supabaseEnabled && isSupabaseValid {
                let key = editingProject?.supabase?.tokenKeychainKey ?? "supabase_\(projectID)"
                if !sbToken.isEmpty {
                    try await keychain.setToken(sbToken, forKey: key)
                }
                let regionTrim = sbRegion.trimmingCharacters(in: .whitespaces)
                supabaseRef = SupabaseRef(
                    projectRef: sbProjectRef.trimmingCharacters(in: .whitespaces),
                    region: regionTrim.isEmpty ? nil : regionTrim,
                    tokenKeychainKey: key
                )
            }

            if netlifyEnabled && isNetlifyValid {
                let key = editingProject?.netlify?.tokenKeychainKey ?? "netlify_\(projectID)"
                if !nfToken.isEmpty {
                    try await keychain.setToken(nfToken, forKey: key)
                }
                let siteNameTrim = nfSiteName.trimmingCharacters(in: .whitespaces)
                netlifyRef = NetlifyRef(
                    siteId: nfSiteId.trimmingCharacters(in: .whitespaces),
                    siteName: siteNameTrim.isEmpty ? nil : siteNameTrim,
                    tokenKeychainKey: key
                )
            }
        } catch {
            errorMessage = "Keychain save failed: \(error.localizedDescription)"
            return
        }

        let trimmedClient = clientName.trimmingCharacters(in: .whitespaces)
        let trimmedNotes  = notes.trimmingCharacters(in: .whitespaces)

        if let existing = editingProject {
            var updated = existing
            updated.name       = name.trimmingCharacters(in: .whitespaces)
            updated.clientName = trimmedClient.isEmpty ? nil : trimmedClient
            updated.notes      = trimmedNotes.isEmpty  ? nil : trimmedNotes
            updated.github     = githubRef
            updated.supabase   = supabaseRef
            updated.netlify    = netlifyRef
            fleetService.updateProject(updated)
        } else {
            let project = FleetProject(
                id: projectID,
                name: name.trimmingCharacters(in: .whitespaces),
                clientName: trimmedClient.isEmpty ? nil : trimmedClient,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                github: githubRef,
                supabase: supabaseRef,
                netlify: netlifyRef
            )
            fleetService.addProject(project)
        }

        dismiss()

        let refreshID = projectID
        Task {
            await fleetService.refreshHealth(for: refreshID)
        }
    }
}
