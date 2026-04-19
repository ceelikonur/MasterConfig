import SwiftUI
import Charts

// MARK: - Design Tokens

private extension Color {
    static let bgPrimary     = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let surface       = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let surfaceRaised = Color(red: 0.16, green: 0.17, blue: 0.22)
    static let accent        = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let textPrimary   = Color(red: 0.75, green: 0.80, blue: 0.97)
    static let textSecondary = Color(red: 0.34, green: 0.37, blue: 0.55)
    static let divider       = Color(red: 0.18, green: 0.20, blue: 0.28)
    static let budgetGreen   = Color(red: 0.62, green: 0.81, blue: 0.42)
    static let budgetYellow  = Color(red: 0.97, green: 0.80, blue: 0.35)
    static let budgetRed     = Color(red: 0.97, green: 0.40, blue: 0.40)
}

private extension BudgetStatus {
    var uiColor: Color {
        switch self {
        case .ok:       return .budgetGreen
        case .warning:  return .budgetYellow
        case .exceeded: return .budgetRed
        case .noLimit:  return .textSecondary
        }
    }
    var label: String {
        switch self {
        case .ok:       return "OK"
        case .warning:  return "Warning"
        case .exceeded: return "Exceeded"
        case .noLimit:  return "No Limit"
        }
    }
    var icon: String {
        switch self {
        case .ok:       return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .exceeded: return "xmark.octagon.fill"
        case .noLimit:  return "minus.circle"
        }
    }
}

// MARK: - CostsView

struct CostsView: View {
    @Environment(BudgetService.self) private var budget

    @State private var selectedAgent: String? = nil
    @State private var editingAgent: String   = ""
    @State private var editMonthlyLimit: String  = ""
    @State private var editSoftAlert: String     = "80"
    @State private var editAutoPause: Bool       = false
    @State private var filterAgent: String = "All"
    @State private var chartDays: Int = 14

    private var allAgentsForFilter: [String] { ["All"] + budget.knownAgents }

    var body: some View {
        HSplitView {
            mainContent
                .frame(minWidth: 500)
            if selectedAgent != nil {
                budgetConfigPanel
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            }
        }
        .background(Color.bgPrimary)
        .task { budget.load() }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Main Content (left)
    // ─────────────────────────────────────────────────────────────

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow
                statCards
                agentTable
                spendChart
                costLog
            }
            .padding(20)
        }
        .background(Color.bgPrimary)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            Label("Cost Tracking", systemImage: "dollarsign.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button { budget.load() } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    // MARK: Stat Cards

    private var statCards: some View {
        let agents         = budget.knownAgents
        let thisMonth      = budget.totalCost(period: "monthly")
        let today          = budget.totalCost(period: "daily")
        let avgPerAgent    = agents.isEmpty ? 0 : thisMonth / Double(agents.count)

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
            spacing: 12
        ) {
            statCard("This Month",    value: "$\(String(format: "%.2f", thisMonth))",   icon: "calendar",          color: .accent)
            statCard("Today",         value: "$\(String(format: "%.4f", today))",       icon: "sun.max",           color: .budgetGreen)
            statCard("Active Agents", value: "\(agents.count)",                         icon: "person.2",          color: .budgetYellow)
            statCard("Avg/Agent",     value: "$\(String(format: "%.2f", avgPerAgent))", icon: "chart.bar",         color: .budgetRed)
        }
    }

    private func statCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Color.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(10)
    }

    // MARK: Agent Table

    private var agentTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent Budgets")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            if budget.knownAgents.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(Color.textSecondary)
                    Text("No agents yet. Costs logged via MCP will appear here.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface)
                .cornerRadius(10)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    HStack {
                        Text("Agent").frame(minWidth: 120, alignment: .leading)
                        Text("Limit").frame(width: 70, alignment: .trailing)
                        Text("Spent").frame(width: 70, alignment: .trailing)
                        Text("Remaining").frame(width: 80, alignment: .trailing)
                        Spacer()
                        Text("Status").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider().overlay(Color.divider)

                    ForEach(budget.knownAgents, id: \.self) { agent in
                        agentRow(agent)
                        if agent != budget.knownAgents.last {
                            Divider().overlay(Color.divider).padding(.horizontal, 14)
                        }
                    }
                }
                .background(Color.surface)
                .cornerRadius(10)
            }
        }
    }

    private func agentRow(_ agent: String) -> some View {
        let config  = budget.budgets[agent]
        let spent   = config?.currentSpendUSD ?? budget.totalCost(agentName: agent)
        let limit   = config?.monthlyLimitUSD
        let ratio   = budget.spendRatio(for: agent)
        let status  = budget.budgetStatus(for: agent)
        let isSelected = selectedAgent == agent

        return Button {
            if selectedAgent == agent {
                selectedAgent = nil
            } else {
                selectedAgent = agent
                populateEditFields(for: agent)
            }
        } label: {
            HStack(spacing: 8) {
                Text(agent)
                    .font(.system(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accent : Color.textPrimary)
                    .frame(minWidth: 120, alignment: .leading)
                    .lineLimit(1)

                Text(limit.map { "$\(String(format: "%.0f", $0))" } ?? "—")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 70, alignment: .trailing)

                Text("$\(String(format: "%.2f", spent))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 70, alignment: .trailing)

                // Remaining
                if let lim = limit {
                    let remaining = max(lim - spent, 0)
                    Text("$\(String(format: "%.2f", remaining))")
                        .font(.callout)
                        .foregroundStyle(remaining < lim * 0.2 ? Color.budgetRed : Color.textSecondary)
                        .frame(width: 80, alignment: .trailing)
                } else {
                    Text("—").font(.callout).foregroundStyle(Color.textSecondary).frame(width: 80, alignment: .trailing)
                }

                // Progress bar
                if limit != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.divider)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor(ratio: ratio))
                                .frame(width: geo.size.width * ratio, height: 6)
                        }
                    }
                    .frame(height: 6)
                } else {
                    Spacer()
                }

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                        .font(.caption2)
                    Text(status.label)
                        .font(.caption2)
                }
                .foregroundStyle(status.uiColor)
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func progressColor(ratio: Double) -> Color {
        if ratio >= 1.0 { return .budgetRed }
        if ratio >= 0.8 { return .budgetYellow }
        return .budgetGreen
    }

    // MARK: Spend Chart

    private var spendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Spend")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: $chartDays) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            let data = budget.dailyCosts(last: chartDays)

            if data.allSatisfy({ $0.total == 0 }) {
                Text("No spend data yet.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.surface)
                    .cornerRadius(10)
            } else {
                Chart(data, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Cost USD", item.total)
                    )
                    .foregroundStyle(Color.accent.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(chartDays / 7, 1))) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(Color.textSecondary)
                        AxisGridLine().foregroundStyle(Color.divider)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(String(format: "%.3f", v))")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        AxisGridLine().foregroundStyle(Color.divider)
                    }
                }
                .frame(height: 140)
                .padding(14)
                .background(Color.surface)
                .cornerRadius(10)
            }
        }
    }

    // MARK: Cost Log

    private var costLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Costs")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("Agent", selection: $filterAgent) {
                    ForEach(allAgentsForFilter, id: \.self) { a in
                        Text(a).tag(a)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
            }

            let entries: [CostEntry] = {
                let all = budget.recentCosts
                if filterAgent == "All" { return all }
                return all.filter { $0.agentName == filterAgent }
            }()

            if entries.isEmpty {
                Text("No cost entries yet.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface)
                    .cornerRadius(10)
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("Agent").frame(width: 100, alignment: .leading)
                        Text("Model").frame(width: 140, alignment: .leading)
                        Text("Tokens").frame(width: 100, alignment: .trailing)
                        Text("Cost").frame(width: 70, alignment: .trailing)
                        Spacer()
                        Text("Time").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider().overlay(Color.divider)

                    ForEach(entries.prefix(50)) { entry in
                        costEntryRow(entry)
                        if entry.id != entries.prefix(50).last?.id {
                            Divider().overlay(Color.divider).padding(.horizontal, 14)
                        }
                    }
                }
                .background(Color.surface)
                .cornerRadius(10)
            }
        }
    }

    private func costEntryRow(_ entry: CostEntry) -> some View {
        HStack {
            Text(entry.agentName)
                .font(.callout)
                .foregroundStyle(Color.accent)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            Text(entry.model)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)

            Text("\(entry.inputTokens + entry.outputTokens)")
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .frame(width: 100, alignment: .trailing)

            Text("$\(String(format: "%.4f", entry.costUSD))")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 70, alignment: .trailing)

            Spacer()

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Right Panel — Budget Config
    // ─────────────────────────────────────────────────────────────

    private var budgetConfigPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Budget Config")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button { selectedAgent = nil } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider().overlay(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let agent = selectedAgent {
                        // Agent info
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agent")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(agent)
                                .font(.title3.bold())
                                .foregroundStyle(Color.accent)
                        }

                        let status = budget.budgetStatus(for: agent)
                        HStack(spacing: 6) {
                            Image(systemName: status.icon)
                            Text(status.label)
                        }
                        .font(.caption)
                        .foregroundStyle(status.uiColor)

                        Divider().overlay(Color.divider)

                        // Edit fields
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Monthly Limit (USD)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            HStack {
                                Text("$").foregroundStyle(Color.textSecondary)
                                TextField("50.00", text: $editMonthlyLimit)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .padding(8)
                            .background(Color.surface)
                            .cornerRadius(7)

                            Text("Soft Alert Threshold (\(editSoftAlert)%)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)

                            if let val = Double(editSoftAlert) {
                                Slider(value: Binding(
                                    get: { val / 100 },
                                    set: { editSoftAlert = String(Int($0 * 100)) }
                                ), in: 0.1...0.99, step: 0.05)
                                .tint(Color.budgetYellow)
                            }

                            Toggle("Auto-Pause on Exceed", isOn: $editAutoPause)
                                .font(.callout)
                                .foregroundStyle(Color.textPrimary)
                                .tint(Color.accent)
                        }

                        // Save button
                        Button {
                            guard
                                let agent = selectedAgent,
                                let limit = Double(editMonthlyLimit),
                                let alert = Double(editSoftAlert)
                            else { return }
                            budget.setBudget(
                                agentName: agent,
                                monthlyLimitUSD: limit,
                                softAlertThreshold: alert / 100,
                                autoPauseEnabled: editAutoPause
                            )
                        } label: {
                            Text("Save Budget")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editMonthlyLimit.isEmpty || Double(editMonthlyLimit) == nil)

                        Divider().overlay(Color.divider)

                        // Current period summary
                        if let config = budget.budgets[agent] {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This Month")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)

                                configMetaRow("Spent", "$\(String(format: "%.4f", config.currentSpendUSD))")
                                configMetaRow("Remaining", "$\(String(format: "%.4f", max(config.monthlyLimitUSD - config.currentSpendUSD, 0)))")
                                configMetaRow("Input Tokens", "\(config.tokenUsage.inputTokens)")
                                configMetaRow("Output Tokens", "\(config.tokenUsage.outputTokens)")

                                // Spend bar
                                let ratio = budget.spendRatio(for: agent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Int(ratio * 100))% used")
                                        .font(.caption2)
                                        .foregroundStyle(progressColor(ratio: ratio))
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.divider)
                                                .frame(height: 8)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(progressColor(ratio: ratio))
                                                .frame(width: geo.size.width * ratio, height: 8)
                                        }
                                    }
                                    .frame(height: 8)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Color.bgPrimary)
    }

    private func configMetaRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Helpers

    private func populateEditFields(for agent: String) {
        editingAgent = agent
        if let config = budget.budgets[agent] {
            editMonthlyLimit = String(format: "%.2f", config.monthlyLimitUSD)
            editSoftAlert    = String(Int(config.softAlertThreshold * 100))
            editAutoPause    = config.autoPauseEnabled
        } else {
            editMonthlyLimit = "50.00"
            editSoftAlert    = "80"
            editAutoPause    = false
        }
    }
}
