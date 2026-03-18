import SwiftUI

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary = Color(red: 0.1, green: 0.11, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let statusGreen = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let statusBlue = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let statusGray = Color(red: 0.34, green: 0.37, blue: 0.54)
    static let statusRed = Color(red: 0.97, green: 0.47, blue: 0.56)
    static let statusOrange = Color(red: 0.95, green: 0.68, blue: 0.32)
}

// MARK: - AgentCardView

struct AgentCardView: View {
    let agent: AgentInstance
    let onKill: () -> Void
    let onReadOutput: () async -> String

    @State private var isHovered = false
    @State private var showOutputSheet = false
    @State private var showKillConfirm = false
    @State private var outputText = ""
    @State private var isLoadingOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: name + status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)

                Text(agent.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(agent.status.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .cornerRadius(4)
            }

            // Repo path
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(agent.repoName)
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            // Current task
            if let task = agent.currentTask, !task.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 1)
                    Text(task)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            // Stats row
            HStack(spacing: 14) {
                Label("\(agent.messageCount)", systemImage: "message")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)

                Label(agent.spawnedAt.formatted(date: .omitted, time: .shortened),
                      systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)

                Spacer()
            }

            Divider()
                .background(Color.textSecondary.opacity(0.2))

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    isLoadingOutput = true
                    Task {
                        outputText = await onReadOutput()
                        isLoadingOutput = false
                        showOutputSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isLoadingOutput {
                            ProgressView()
                                .scaleEffect(0.5)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "terminal")
                                .font(.caption2)
                        }
                        Text("Read Output")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isLoadingOutput)

                Spacer()

                Button(role: .destructive) {
                    showKillConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.caption2)
                        Text("Kill")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHovered ? Color.accent.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .shadow(color: isHovered ? Color.accent.opacity(0.08) : Color.clear, radius: 8, y: 2)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .alert("Kill Agent", isPresented: $showKillConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Kill", role: .destructive) { onKill() }
        } message: {
            Text("Are you sure you want to kill agent \"\(agent.name)\"? This will terminate its Claude CLI process.")
        }
        .sheet(isPresented: $showOutputSheet) {
            AgentOutputSheet(agentName: agent.name, output: outputText)
        }
    }

    private var statusColor: Color {
        switch agent.status {
        case .starting: return .statusGray
        case .idle: return .statusGreen
        case .working: return .statusBlue
        case .blocked: return .statusOrange
        case .completed: return .statusGreen
        case .dead: return .statusRed
        case .orphan: return .statusOrange
        }
    }
}

// MARK: - Agent Output Sheet

private struct AgentOutputSheet: View {
    let agentName: String
    let output: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(Color.accent)
                Text("Output: \(agentName)")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Output content
            ScrollView {
                Text(output.isEmpty ? "(no output)" : output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? Color.textSecondary : Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
        .frame(width: 600, height: 400)
    }
}
