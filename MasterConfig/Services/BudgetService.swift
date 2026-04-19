import Foundation

// MARK: - Budget Service

@Observable
@MainActor
final class BudgetService {

    // Published state
    var budgets: [String: BudgetConfig] = [:]   // agentName -> config
    var recentCosts: [CostEntry] = []
    var isLoading = false

    private let fm = FileManager.default
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    // MARK: - Paths

    private var baseDir: String  { NSHomeDirectory() + "/.claude/orchestrator/budgets" }
    private var configFile: String { baseDir + "/config.json" }
    private var costsDir: String { baseDir + "/costs" }

    // MARK: - Bootstrap

    func load() {
        isLoading = true
        defer { isLoading = false }
        ensureDirs()
        loadBudgets()
        loadRecentCosts()
    }

    private func ensureDirs() {
        [baseDir, costsDir].forEach {
            try? fm.createDirectory(atPath: $0, withIntermediateDirectories: true)
        }
    }

    // MARK: - Loaders

    private func loadBudgets() {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
            let decoded = try? JSONDecoder.iso.decode([String: BudgetConfig].self, from: data)
        else { budgets = [:]; return }
        budgets = decoded
    }

    private func loadRecentCosts(limit: Int = 100) {
        let costs = readJsonl(costsDir + "/\(currentMonthKey()).jsonl")
        recentCosts = Array(costs.suffix(limit).reversed())
    }

    // MARK: - JSONL reader

    func readJsonl(_ path: String) -> [CostEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONDecoder.iso.decode(CostEntry.self, from: Data(line.utf8))
            }
    }

    // MARK: - Save budgets (atomic)

    func saveBudgets() {
        guard let data = try? JSONEncoder.iso.encode(budgets) else { return }
        let tmp = configFile + ".tmp"
        let dest = URL(fileURLWithPath: configFile)
        let tmpURL = URL(fileURLWithPath: tmp)
        try? data.write(to: tmpURL, options: .atomic)
        if fm.fileExists(atPath: configFile) {
            _ = try? fm.replaceItemAt(dest, withItemAt: tmpURL)
        } else {
            try? fm.moveItem(at: tmpURL, to: dest)
        }
    }

    // MARK: - Cost Logging

    func logCost(
        agentName: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        model: String,
        projectId: String? = nil,
        issueId: String? = nil
    ) {
        let entry = CostEntry(
            agentName: agentName,
            projectId: projectId,
            issueId: issueId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            model: model
        )

        // Append to JSONL
        appendToJsonl(entry)

        // Update in-memory budget config
        var config = budgets[agentName] ?? BudgetConfig()
        config.currentSpendUSD += costUSD
        config.tokenUsage.inputTokens  += inputTokens
        config.tokenUsage.outputTokens += outputTokens
        config.tokenUsage.totalCostUSD += costUSD
        config.tokenUsage.lastUpdated  = Date()
        budgets[agentName] = config
        saveBudgets()

        // Keep recentCosts in sync
        recentCosts.insert(entry, at: 0)
        if recentCosts.count > 200 { recentCosts = Array(recentCosts.prefix(200)) }
    }

    private func appendToJsonl(_ entry: CostEntry) {
        let path = costsDir + "/\(currentMonthKey()).jsonl"
        guard
            let data = try? JSONEncoder.iso.encode(entry),
            let line = String(data: data, encoding: .utf8)
        else { return }

        let lineWithNL = line + "\n"
        if fm.fileExists(atPath: path) {
            guard let fh = FileHandle(forWritingAtPath: path) else { return }
            fh.seekToEndOfFile()
            fh.write(Data(lineWithNL.utf8))
            fh.closeFile()
        } else {
            try? lineWithNL.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Budget Configuration

    func setBudget(
        agentName: String,
        monthlyLimitUSD: Double,
        softAlertThreshold: Double = 0.8,
        autoPauseEnabled: Bool = false
    ) {
        var config = budgets[agentName] ?? BudgetConfig()
        config.monthlyLimitUSD     = monthlyLimitUSD
        config.softAlertThreshold  = softAlertThreshold
        config.autoPauseEnabled    = autoPauseEnabled
        budgets[agentName] = config
        saveBudgets()
    }

    func budgetStatus(for agentName: String) -> BudgetStatus {
        guard let config = budgets[agentName] else { return .noLimit }
        guard config.monthlyLimitUSD > 0 else { return .noLimit }
        let ratio = config.currentSpendUSD / config.monthlyLimitUSD
        if ratio >= 1.0 { return .exceeded }
        if ratio >= config.softAlertThreshold { return .warning }
        return .ok
    }

    func spendRatio(for agentName: String) -> Double {
        guard let config = budgets[agentName], config.monthlyLimitUSD > 0 else { return 0 }
        return min(config.currentSpendUSD / config.monthlyLimitUSD, 1.0)
    }

    // MARK: - Reporting

    func totalCost(agentName: String? = nil, period: String = "monthly") -> Double {
        costsForPeriod(period, agentName: agentName).reduce(0) { $0 + $1.costUSD }
    }

    func costsForPeriod(_ period: String, agentName: String? = nil) -> [CostEntry] {
        let all = allCurrentMonthCosts()
        let filtered = agentName == nil ? all : all.filter { $0.agentName == agentName }
        switch period {
        case "daily":
            let today = Calendar.current.startOfDay(for: Date())
            return filtered.filter { $0.timestamp >= today }
        case "weekly":
            let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            return filtered.filter { $0.timestamp >= weekAgo }
        default:
            return filtered
        }
    }

    func allCurrentMonthCosts() -> [CostEntry] {
        readJsonl(costsDir + "/\(currentMonthKey()).jsonl")
    }

    /// Returns (date, totalCostUSD) tuples for the last `days` days (ascending)
    func dailyCosts(last days: Int = 30) -> [(date: Date, total: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Gather costs from this + previous month
        var allCosts: [CostEntry] = []
        for offset in 0...1 {
            if let d = cal.date(byAdding: .month, value: -offset, to: today) {
                allCosts += readJsonl(costsDir + "/\(monthKey(for: d)).jsonl")
            }
        }

        return (0..<days).compactMap { i -> (Date, Double)? in
            guard let day = cal.date(byAdding: .day, value: -(days - 1 - i), to: today),
                  let nextDay = cal.date(byAdding: .day, value: 1, to: day)
            else { return nil }
            let dayTotal = allCosts
                .filter { $0.timestamp >= day && $0.timestamp < nextDay }
                .reduce(0) { $0 + $1.costUSD }
            return (day, dayTotal)
        }
    }

    // MARK: - Helpers

    var knownAgents: [String] {
        let fromBudgets = Array(budgets.keys)
        let fromCosts   = Array(Set(allCurrentMonthCosts().map { $0.agentName }))
        return Array(Set(fromBudgets + fromCosts)).sorted()
    }

    private func currentMonthKey() -> String { monthKey(for: Date()) }
    private func monthKey(for date: Date) -> String { monthFormatter.string(from: date) }
}
