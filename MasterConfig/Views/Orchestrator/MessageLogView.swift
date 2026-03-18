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
    static let statusPurple = Color(red: 0.68, green: 0.51, blue: 0.92)
}

// MARK: - MessageLogView

struct MessageLogView: View {
    let messages: [AgentMessage]

    @State private var filterAgent: String = ""
    @State private var scrolledToBottom = true

    private var filteredMessages: [AgentMessage] {
        if filterAgent.isEmpty {
            return messages
        }
        return messages.filter { msg in
            msg.from.localizedCaseInsensitiveContains(filterAgent)
            || msg.to.localizedCaseInsensitiveContains(filterAgent)
        }
    }

    private var uniqueAgents: [String] {
        var names = Set<String>()
        for msg in messages {
            names.insert(msg.from)
            names.insert(msg.to)
        }
        return names.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(Color.accent)
                Text("Message Log")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text("\(filteredMessages.count)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                // Filter picker
                Menu {
                    Button("All Agents") {
                        filterAgent = ""
                    }

                    Divider()

                    ForEach(uniqueAgents, id: \.self) { agent in
                        Button(agent) {
                            filterAgent = agent
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.caption)
                        Text(filterAgent.isEmpty ? "Filter" : filterAgent)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        filterAgent.isEmpty
                            ? Color.textSecondary.opacity(0.1)
                            : Color.accent.opacity(0.15)
                    )
                    .foregroundStyle(filterAgent.isEmpty ? Color.textSecondary : Color.accent)
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Message list
            if filteredMessages.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundStyle(Color.textSecondary)
                    Text("No messages yet")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredMessages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if scrolledToBottom, let lastMsg = filteredMessages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastMsg.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let lastMsg = filteredMessages.last {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Message Row

    private func messageRow(_ message: AgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)

                // From -> To
                Text(message.from)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textSecondary)

                Text(message.to)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                // Type badge
                Text(message.messageType.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(messageTypeColor(message.messageType).opacity(0.15))
                    .foregroundStyle(messageTypeColor(message.messageType))
                    .cornerRadius(3)

                Spacer()
            }

            // Content
            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textPrimary.opacity(0.85))
                .lineLimit(4)
                .padding(.leading, 2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bgPrimary.opacity(0.5))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private func messageTypeColor(_ type: AgentMessage.MessageType) -> Color {
        switch type {
        case .task: return .statusBlue
        case .result: return .statusGreen
        case .context: return .statusPurple
        case .question: return .statusOrange
        case .status: return .statusGray
        case .shutdown: return .statusRed
        }
    }
}
