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
                    sessionDetail(session: session)
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
        .onAppear {
            // Auto-test: write debug log when Terminal tab appears
            let msg = "[\(Date())] ChatView appeared\n"
            let path = "/tmp/mc-debug.log"
            if let data = msg.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: path) {
                    if let fh = FileHandle(forWritingAtPath: path) { fh.seekToEndOfFile(); fh.write(data); fh.closeFile() }
                } else {
                    FileManager.default.createFile(atPath: path, contents: data)
                }
            }
        }
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
        SessionDetailView(session: session, onClose: { handleClose(session) })
    }

    // MARK: - Session Sidebar

    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
            Text("Open a new Claude session in terminal.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                terminalService.newSession(title: "Claude")
                selectedSessionID = terminalService.sessions.last?.id
            } label: {
                Label("Open Claude in Terminal", systemImage: "terminal.fill")
            }
            .buttonStyle(.borderedProminent)

            Button("New Session (with options)") { showNewSessionSheet = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        terminalService.closeSession(session.id)
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
                .fill(session.isRunning ? Color.green : Color.gray)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

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
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Session")
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @Environment(TerminalService.self) private var terminalService
    let session: TerminalSession
    let onClose: () -> Void

    @State private var refreshTimer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(session.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(session.title)
                    .font(.title3.weight(.semibold))

                if let repoPath = session.repoPath {
                    Divider().frame(height: 16)
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(URL(fileURLWithPath: repoPath).lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await terminalService.refreshOutput(sessionID: session.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh output")

                Text("PID: \(session.processRef)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                Button(role: .destructive) {
                    onClose()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Kill Session")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Terminal output preview
            if session.lastOutput.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Waiting for output...")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Text("Process \(session.processRef) running")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    Text(session.lastOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(NSColor.labelColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
        .onAppear {
            Task { await terminalService.refreshOutput(sessionID: session.id) }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { await terminalService.refreshOutput(sessionID: session.id) }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
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
                            Text("-- None --").tag(Optional<Repo>.none)
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
