import SwiftUI

// MARK: - Add Project Sheet

struct FleetAddProjectSheet: View {
    @Environment(FleetService.self) private var fleetService
    @Environment(\.dismiss) private var dismiss

    // Basics
    @State private var name = ""
    @State private var clientName = ""
    @State private var notes = ""

    // GitHub
    @State private var githubEnabled = false
    @State private var ghOwner = ""
    @State private var ghRepo = ""
    @State private var ghBranch = ""
    @State private var ghToken = ""

    // Supabase
    @State private var supabaseEnabled = false
    @State private var sbProjectRef = ""
    @State private var sbRegion = ""
    @State private var sbToken = ""

    // Netlify
    @State private var netlifyEnabled = false
    @State private var nfSiteId = ""
    @State private var nfSiteName = ""
    @State private var nfToken = ""

    // Submit state
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // MARK: - Validation

    private var isGithubValid: Bool {
        githubEnabled &&
        !ghOwner.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ghRepo.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ghToken.isEmpty
    }

    private var isSupabaseValid: Bool {
        supabaseEnabled &&
        !sbProjectRef.trimmingCharacters(in: .whitespaces).isEmpty &&
        !sbToken.isEmpty
    }

    private var isNetlifyValid: Bool {
        netlifyEnabled &&
        !nfSiteId.trimmingCharacters(in: .whitespaces).isEmpty &&
        !nfToken.isEmpty
    }

    private var canSubmit: Bool {
        let nameOk = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let anyIntegration = isGithubValid || isSupabaseValid || isNetlifyValid
        return nameOk && anyIntegration && !isSubmitting
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
                        SecureField("Personal Access Token", text: $ghToken)
                    }
                } header: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Section {
                    Toggle("Enable Supabase", isOn: $supabaseEnabled.animation(.easeInOut(duration: 0.15)))
                    if supabaseEnabled {
                        TextField("Project ref", text: $sbProjectRef)
                        TextField("Region (optional)", text: $sbRegion)
                        SecureField("Management API PAT", text: $sbToken)
                    }
                } header: {
                    Label("Supabase", systemImage: "cylinder.split.1x2")
                }

                Section {
                    Toggle("Enable Netlify", isOn: $netlifyEnabled.animation(.easeInOut(duration: 0.15)))
                    if netlifyEnabled {
                        TextField("Site ID", text: $nfSiteId)
                        TextField("Site name (optional)", text: $nfSiteName)
                        SecureField("Personal Access Token", text: $nfToken)
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
            Label("Add Fleet Project", systemImage: "shippingbox.and.arrow.backward")
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
                Text("Add Project")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let projectID = UUID().uuidString
        let keychain = KeychainService.shared

        var githubRef: GitHubRef?
        var supabaseRef: SupabaseRef?
        var netlifyRef: NetlifyRef?

        do {
            if isGithubValid {
                let key = "github_\(projectID)"
                try await keychain.setToken(ghToken, forKey: key)
                let branchTrim = ghBranch.trimmingCharacters(in: .whitespaces)
                githubRef = GitHubRef(
                    owner: ghOwner.trimmingCharacters(in: .whitespaces),
                    repo: ghRepo.trimmingCharacters(in: .whitespaces),
                    defaultBranch: branchTrim.isEmpty ? nil : branchTrim,
                    tokenKeychainKey: key
                )
            }

            if isSupabaseValid {
                let key = "supabase_\(projectID)"
                try await keychain.setToken(sbToken, forKey: key)
                let regionTrim = sbRegion.trimmingCharacters(in: .whitespaces)
                supabaseRef = SupabaseRef(
                    projectRef: sbProjectRef.trimmingCharacters(in: .whitespaces),
                    region: regionTrim.isEmpty ? nil : regionTrim,
                    tokenKeychainKey: key
                )
            }

            if isNetlifyValid {
                let key = "netlify_\(projectID)"
                try await keychain.setToken(nfToken, forKey: key)
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

        let project = FleetProject(
            id: projectID,
            name: name.trimmingCharacters(in: .whitespaces),
            clientName: clientName.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : clientName.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespaces),
            github: githubRef,
            supabase: supabaseRef,
            netlify: netlifyRef
        )

        fleetService.addProject(project)
        dismiss()

        Task {
            await fleetService.refreshHealth(for: project.id)
        }
    }
}
