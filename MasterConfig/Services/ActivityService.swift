import Foundation

// MARK: - Activity Service

@Observable
@MainActor
final class ActivityService {

    var entries:   [ActivityEntry] = []
    var isLoading  = false

    private let fm = FileManager.default

    // MARK: - Paths

    private var activityFile: String { NSHomeDirectory() + "/.claude/orchestrator/activity.jsonl" }
    private var baseDir:      String { NSHomeDirectory() + "/.claude/orchestrator" }

    // MARK: - Bootstrap

    func load(limit: Int = 500) {
        isLoading = true
        defer { isLoading = false }
        ensureDir()
        tailRead(limit: limit)
    }

    private func ensureDir() {
        try? fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Tail Read (efficient for large JSONL files)

    private func tailRead(limit: Int) {
        guard fm.fileExists(atPath: activityFile) else { entries = []; return }
        guard let handle = FileHandle(forReadingAtPath: activityFile) else { entries = []; return }
        defer { handle.closeFile() }

        let fileSize   = handle.seekToEndOfFile()
        let chunkSize: UInt64 = min(fileSize, 1_024 * 1_024)  // up to 1 MB from tail
        handle.seek(toFileOffset: fileSize > chunkSize ? fileSize - chunkSize : 0)
        let data = handle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else { entries = []; return }

        let decoded = text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(limit)
            .compactMap { line -> ActivityEntry? in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder.iso.decode(ActivityEntry.self, from: d)
            }
            .sorted { $0.timestamp > $1.timestamp }

        entries = decoded
    }

    // MARK: - Log

    @discardableResult
    func log(
        type: ActivityType,
        actor: String,
        summary: String,
        metadata: [String: String] = [:]
    ) -> ActivityEntry {
        let entry = ActivityEntry(type: type, actor: actor, summary: summary, metadata: metadata)

        // Prepend in memory (newest first)
        entries.insert(entry, at: 0)
        if entries.count > 1000 { entries = Array(entries.prefix(1000)) }

        // Append to JSONL file
        appendEntry(entry)
        return entry
    }

    private func appendEntry(_ entry: ActivityEntry) {
        guard let data = try? JSONEncoder.iso.encode(entry),
              let line  = String(data: data, encoding: .utf8)
        else { return }

        let text = line + "\n"
        if let handle = FileHandle(forWritingAtPath: activityFile) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            handle.closeFile()
        } else {
            // File doesn't exist yet — create it
            try? text.write(toFile: activityFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Filtering

    func filtered(
        category: ActivityCategory = .all,
        actor: String? = nil,
        since: Date? = nil
    ) -> [ActivityEntry] {
        entries.filter { e in
            let catOK   = category == .all || e.type.category == category
            let actorOK = actor == nil || actor!.isEmpty || e.actor.lowercased().contains(actor!.lowercased())
            let dateOK  = since == nil || e.timestamp >= since!
            return catOK && actorOK && dateOK
        }
    }

    /// Unique actor names seen in recent entries
    var knownActors: [String] {
        let names = Set(entries.prefix(500).map { $0.actor })
        return names.sorted()
    }

    // MARK: - Grouping helpers for UI

    enum TimeGroup: String, CaseIterable {
        case today     = "Today"
        case yesterday = "Yesterday"
        case thisWeek  = "This Week"
        case older     = "Older"
    }

    static func timeGroup(for date: Date) -> TimeGroup {
        let cal  = Calendar.current
        let now  = Date()
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        if date >= weekAgo             { return .thisWeek }
        return .older
    }

    func grouped(entries: [ActivityEntry]) -> [(group: TimeGroup, entries: [ActivityEntry])] {
        let byGroup = Dictionary(grouping: entries) { Self.timeGroup(for: $0.timestamp) }
        return TimeGroup.allCases.compactMap { g in
            guard let items = byGroup[g], !items.isEmpty else { return nil }
            return (group: g, entries: items)
        }
    }
}
