import SwiftUI

// MARK: - ChatView

struct ChatView: View {
    @Environment(TerminalService.self) private var terminalService
    @Environment(RepoService.self) private var repoService

    @State private var selectedSessionID: UUID? = nil
    @State private var showNewSessionSheet = false

    var body: some View {
        HSplitView {
            sessionSidebar
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 240)

            Group {
                if let sid = selectedSessionID,
                   let session = terminalService.sessions.first(where: { $0.id == sid }) {
                    if session.isOrphan {
                        orphanPrompt(session: session)
                    } else {
                        sessionDetail(session: session)
                    }
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewSessionSheet { title, repoPath, options in
                terminalService.newSession(title: title, repoPath: repoPath, options: options)
                selectedSessionID = terminalService.sessions.last?.id
                showNewSessionSheet = false
            }
        }
        .alert("Terminal Error", isPresented: .init(
            get: { terminalService.lastError != nil },
            set: { if !$0 { terminalService.lastError = nil } }
        )) {
            Button("OK") { terminalService.lastError = nil }
        } message: {
            Text(terminalService.lastError ?? "")
        }
        .onAppear {
            if selectedSessionID == nil {
                selectedSessionID = terminalService.sessions.first?.id
            }
        }
        .onChange(of: terminalService.sessions.count) { _, _ in
            if selectedSessionID == nil {
                selectedSessionID = terminalService.sessions.first?.id
            }
        }
        .navigationTitle("Terminal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New Terminal Session")
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }

    // MARK: - Session Detail

    private func sessionDetail(session: TerminalSession) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(session.title)
                        .font(.title2.weight(.semibold))
                }

                Text("tmux: \(session.tmuxName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let repoPath = session.repoPath {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption)
                        Text(repoPath)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Text("This session runs in Terminal.app via tmux.\nClick below to open or re-attach.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    terminalService.openInTerminal(sessionName: session.tmuxName)
                } label: {
                    Label("Open in Terminal", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    handleClose(session)
                } label: {
                    Label("Kill Session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: - Session Sidebar

    private var hasOrphans: Bool {
        terminalService.sessions.contains(where: \.isOrphan)
    }

    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasOrphans {
                    Button {
                        terminalService.killAllOrphans()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Kill All Orphan Sessions")
                }
                Button {
                    showNewSessionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("New Session")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if terminalService.sessions.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No sessions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("New Session") {
                        showNewSessionSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(terminalService.sessions, selection: $selectedSessionID) { session in
                    SessionRow(session: session, onClose: { handleClose(session) })
                        .tag(session.id)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Session Selected")
                .font(.title3.weight(.semibold))
            Text("Create a new session to start chatting with Claude.\nSessions open in Terminal.app via tmux for\nfull native terminal experience.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Session") { showNewSessionSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private func orphanPrompt(session: TerminalSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Orphan Session Detected")
                .font(.title3.weight(.semibold))
            Text("**\(session.tmuxName)** is still running in the background.\nClaude may be actively working and consuming tokens.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    terminalService.attachToOrphan(session.id)
                } label: {
                    Label("Open in Terminal", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    terminalService.killOrphanSession(session.id)
                    selectedSessionID = terminalService.sessions.first?.id
                } label: {
                    Label("Kill Session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private func handleClose(_ session: TerminalSession) {
        if selectedSessionID == session.id {
            let sessions = terminalService.sessions
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                let prev = idx > 0 ? sessions[idx - 1].id : nil
                let next = idx + 1 < sessions.count ? sessions[idx + 1].id : nil
                selectedSessionID = prev ?? next
            }
        }
        if session.isOrphan {
            terminalService.killOrphanSession(session.id)
        } else {
            terminalService.closeSession(session.id)
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: TerminalSession
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isOrphan ? Color.orange : (session.isRunning ? Color.green : Color.gray))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if session.isOrphan {
                        Text("orphan")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let repoPath = session.repoPath {
                    Text(URL(fileURLWithPath: repoPath).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isHovered {
                Button { onClose() } label: {
                    Image(systemName: session.isOrphan ? "trash" : "xmark")
                        .font(.caption2)
                        .foregroundStyle(session.isOrphan ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(session.isOrphan ? "Kill Session" : "Close Session")
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovered = $0 }
    }
}

// MARK: - New Session Sheet

struct NewSessionSheet: View {
    @Environment(RepoService.self) private var repoService
    let onCreate: (String, String?, SessionOptions) -> Void

    @State private var title            = "Claude"
    @State private var useRepo          = false
    @State private var selectedRepo: Repo? = nil
    @State private var skipPermissions  = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(Color.accentColor)
                Text("New Terminal Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Session") {
                    TextField("Name", text: $title)
                }

                Section("Context") {
                    Toggle("Run inside a repository", isOn: $useRepo)
                        .toggleStyle(.switch)

                    if useRepo {
                        Picker("Repository", selection: $selectedRepo) {
                            Text("— None —").tag(Optional<Repo>.none)
                            ForEach(repoService.repos) { repo in
                                Text(repo.name).tag(Optional(repo))
                            }
                        }
                        if let repo = selectedRepo {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(repo.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }

                Section("Options") {
                    Toggle("Skip permission prompts", isOn: $skipPermissions)
                        .toggleStyle(.switch)
                    if skipPermissions {
                        Text("Runs with --dangerously-skip-permissions so Claude can act without confirmations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Claude will ask for permission before file edits, commands, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Create") {
                    let path = useRepo ? selectedRepo?.path : nil
                    let opts = SessionOptions(skipPermissions: skipPermissions)
                    onCreate(title.isEmpty ? "Claude" : title, path, opts)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 420)
    }
}
