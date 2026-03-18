import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let statusGreen = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let statusRed = Color(red: 0.97, green: 0.47, blue: 0.56)
}

// MARK: - EmbeddedTerminalView

struct EmbeddedTerminalView: View {
    let repoPath: String?
    let skipPermissions: Bool

    @State private var outputLines: [TerminalLine] = []
    @State private var inputText: String = ""
    @State private var process: Process?
    @State private var inputPipe: Pipe?
    @State private var isRunning = false
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Circle()
                    .fill(isRunning ? Color.statusGreen : Color.statusRed)
                    .frame(width: 7, height: 7)

                Text(isRunning ? "Running" : "Stopped")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isRunning ? Color.statusGreen : Color.statusRed)

                if let path = repoPath {
                    Divider().frame(height: 12)
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if !outputLines.isEmpty {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear output")
                }

                Button {
                    if isRunning {
                        stopProcess()
                    } else {
                        startProcess()
                    }
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.caption)
                        .foregroundStyle(isRunning ? Color.statusRed : Color.statusGreen)
                }
                .buttonStyle(.plain)
                .help(isRunning ? "Stop process" : "Start process")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surface)

            Divider()

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if outputLines.isEmpty {
                            Text("Terminal ready. Press play to start Claude CLI.")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                                .padding(8)
                        } else {
                            ForEach(outputLines) { line in
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.isError ? Color.statusRed : Color.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: outputLines.count) { _, _ in
                    if let last = outputLines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))

            Divider()

            // Input bar
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.accent)

                TextField("Message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .onSubmit { sendInput() }

                Button { sendInput() } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || !isRunning)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(10)
            .background(Color.surface)
        }
        .alert("Clear Output", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                outputLines.removeAll()
            }
        } message: {
            Text("Clear all terminal output?")
        }
        .onDisappear {
            stopProcess()
        }
    }

    // MARK: - Process Management

    private func startProcess() {
        guard !isRunning else { return }

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        // Find claude binary
        let claudePath = findClaudeBinary()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        var arguments: [String] = []

        // When falling back to /usr/bin/env, prepend "claude" as the command
        if claudePath == "/usr/bin/env" {
            arguments.append("claude")
        }

        if skipPermissions {
            arguments.append("--dangerously-skip-permissions")
        }
        proc.arguments = arguments

        if let path = repoPath {
            proc.currentDirectoryURL = URL(fileURLWithPath: path)
        }

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        proc.environment = env

        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = stdinPipe

        self.inputPipe = stdinPipe
        self.process = proc

        // Read stdout asynchronously
        readPipeAsync(stdoutPipe, isError: false)
        readPipeAsync(stderrPipe, isError: true)

        // Handle termination
        proc.terminationHandler = { [self] _ in
            Task { @MainActor in
                self.isRunning = false
                self.appendLine("--- Process exited with code \(proc.terminationStatus) ---", isError: proc.terminationStatus != 0)
            }
        }

        do {
            try proc.run()
            isRunning = true
            appendLine("--- Claude CLI started ---", isError: false)
        } catch {
            appendLine("Failed to start process: \(error.localizedDescription)", isError: true)
            isRunning = false
        }
    }

    private func stopProcess() {
        guard let proc = process, proc.isRunning else {
            isRunning = false
            return
        }
        proc.terminate()
        isRunning = false
        process = nil
        inputPipe = nil
    }

    private func sendInput() {
        guard !inputText.isEmpty, isRunning, let pipe = inputPipe else { return }

        let text = inputText + "\n"
        inputText = ""

        appendLine("> \(text.trimmingCharacters(in: .newlines))", isError: false)

        if let data = text.data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
    }

    // MARK: - Output Handling

    private func readPipeAsync(_ pipe: Pipe, isError: Bool) {
        let handle = pipe.fileHandleForReading

        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                // EOF
                fileHandle.readabilityHandler = nil
                return
            }

            if let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: .newlines)
                Task { @MainActor in
                    for line in lines where !line.isEmpty {
                        self.appendLine(line, isError: isError)
                    }
                }
            }
        }
    }

    private func appendLine(_ text: String, isError: Bool) {
        let line = TerminalLine(text: text, isError: isError)
        outputLines.append(line)

        // Keep buffer manageable
        if outputLines.count > 5000 {
            outputLines.removeFirst(outputLines.count - 4000)
        }
    }

    // MARK: - Helpers

    private func findClaudeBinary() -> String {
        // Check common locations
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "/usr/bin/claude"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to PATH-based lookup via /usr/bin/env
        return "/usr/bin/env"
    }
}

// MARK: - TerminalLine

private struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}
