import Foundation

// MARK: - Routine Service

@Observable
@MainActor
final class RoutineService {

    // Published state
    var routines: [Routine]    = []
    var logs:     [RoutineLog] = []
    var isLoading              = false

    /// Injected after app startup — needed to create issues when routines fire
    var hierarchyService: HierarchyService?
    /// Injected for activity logging
    var activityService: ActivityService?

    private let fm = FileManager.default
    private var timer: Timer?

    // MARK: - Paths

    private var baseDir:      String { NSHomeDirectory() + "/.claude/orchestrator/routines" }
    private var routinesFile: String { baseDir + "/routines.json" }
    private var logsFile:     String { baseDir + "/logs.jsonl" }

    // MARK: - Bootstrap

    func load() {
        isLoading = true
        defer { isLoading = false }
        ensureDirs()
        loadRoutines()
        loadLogs(limit: 100)
    }

    private func ensureDirs() {
        try? fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Timer

    func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndFire()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Scheduler

    private func checkAndFire() {
        let now = Date()
        for i in routines.indices {
            guard routines[i].enabled else { continue }
            guard let next = routines[i].nextRun, next <= now else { continue }
            fire(index: i)
        }
    }

    func triggerNow(id: String) {
        guard let i = routines.firstIndex(where: { $0.id == id }) else { return }
        fire(index: i)
    }

    private func fire(index i: Int) {
        var routine = routines[i]
        let template = routine.issueTemplate
        let effectiveTitle = template.title.isEmpty ? routine.title : template.title

        var issueId:    String? = nil
        var issueTitle: String? = nil
        var errorMsg:   String? = nil

        if let hs = hierarchyService {
            let issue = hs.createIssue(
                title:          effectiveTitle,
                description:    template.description,
                projectId:      template.projectId,
                milestoneId:    template.milestoneId,
                assignee:       routine.assignee,
                priority:       template.priority,
                labels:         template.labels
            )
            issueId    = issue.id
            issueTitle = issue.title
        } else {
            errorMsg = "HierarchyService not available"
        }

        // Log the run
        let log = RoutineLog(
            routineId:    routine.id,
            routineTitle: routine.title,
            issueId:      issueId,
            issueTitle:   issueTitle,
            success:      errorMsg == nil,
            error:        errorMsg
        )
        logs.insert(log, at: 0)
        if logs.count > 200 { logs = Array(logs.prefix(200)) }
        appendLog(log)

        // Log activity
        activityService?.log(
            type: .routineFired,
            actor: routine.assignee ?? "routine",
            summary: "Routine fired: \(routine.title)\(issueTitle != nil ? " → issue \"\(issueTitle!)\"" : "")",
            metadata: ["routine_id": routine.id, "issue_id": issueId ?? "", "success": errorMsg == nil ? "true" : "false"]
        )

        // Advance timing
        routine.lastRun  = Date()
        routine.nextRun  = Self.computeNextRun(for: routine, after: Date())
        routine.runCount += 1
        routine.updatedAt = Date()
        routines[i] = routine
        persistRoutines()
    }

    // MARK: - Next Run Computation

    static func computeNextRun(for routine: Routine, after date: Date = Date()) -> Date {
        let cal   = Calendar.current
        let sched = routine.schedule

        switch sched.type {
        case .interval:
            let mins = sched.intervalMinutes ?? 60
            return date.addingTimeInterval(Double(mins) * 60)

        case .daily:
            let (h, m) = parseHHMM(sched.timeOfDay ?? "09:00")
            var next = cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
            if next <= date {
                next = cal.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next

        case .weekly:
            let wd        = sched.weekday ?? 1                             // 0=Sun
            let (h, m)    = parseHHMM(sched.timeOfDay ?? "09:00")
            var next      = cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
            let currentWD = cal.component(.weekday, from: date) - 1       // 0=Sun
            var daysAhead = (wd - currentWD + 7) % 7
            if daysAhead == 0 && next <= date { daysAhead = 7 }
            next = cal.date(byAdding: .day, value: daysAhead, to: next) ?? next
            return next

        case .monthly:
            let dom       = max(1, min(sched.dayOfMonth ?? 1, 28))
            let (h, m)    = parseHHMM(sched.timeOfDay ?? "09:00")
            var comps     = cal.dateComponents([.year, .month], from: date)
            comps.day = dom; comps.hour = h; comps.minute = m; comps.second = 0
            var next      = cal.date(from: comps) ?? date
            if next <= date {
                next = cal.date(byAdding: .month, value: 1, to: next) ?? next
            }
            return next
        }
    }

    private static func parseHHMM(_ s: String) -> (Int, Int) {
        let parts = s.split(separator: ":").map { Int($0) ?? 0 }
        let h = parts.count > 0 ? min(parts[0], 23) : 9
        let m = parts.count > 1 ? min(parts[1], 59) : 0
        return (h, m)
    }

    // MARK: - Loaders / Persisters

    private func loadRoutines() {
        guard
            let data  = try? Data(contentsOf: URL(fileURLWithPath: routinesFile)),
            let items = try? JSONDecoder.iso.decode([Routine].self, from: data)
        else { routines = []; return }
        routines = items.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadLogs(limit: Int) {
        guard fm.fileExists(atPath: logsFile) else { logs = []; return }
        guard let text = try? String(contentsOfFile: logsFile, encoding: .utf8) else { logs = []; return }
        let all = text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? JSONDecoder.iso.decode(RoutineLog.self, from: Data($0.utf8)) }
            .sorted { $0.firedAt > $1.firedAt }
        logs = Array(all.prefix(limit))
    }

    private func persistRoutines() {
        guard let data = try? JSONEncoder.iso.encode(routines) else { return }
        atomicWrite(data, to: routinesFile)
    }

    private func appendLog(_ log: RoutineLog) {
        guard let data   = try? JSONEncoder.iso.encode(log),
              let line   = String(data: data, encoding: .utf8)
        else { return }
        let text = line + "\n"
        if let handle = FileHandle(forWritingAtPath: logsFile) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            handle.closeFile()
        } else {
            try? text.write(toFile: logsFile, atomically: true, encoding: .utf8)
        }
    }

    private func atomicWrite(_ data: Data, to path: String) {
        let tmp  = URL(fileURLWithPath: path + ".tmp")
        let dest = URL(fileURLWithPath: path)
        try? data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: path) {
            _ = try? fm.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try? fm.moveItem(at: tmp, to: dest)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func addRoutine(
        title: String,
        description: String = "",
        assignee: String? = nil,
        schedule: RoutineSchedule = RoutineSchedule(),
        issueTemplate: IssueTemplate = IssueTemplate()
    ) -> Routine {
        var r = Routine(
            title: title,
            description: description,
            assignee: assignee,
            schedule: schedule,
            issueTemplate: issueTemplate
        )
        r.nextRun = Self.computeNextRun(for: r, after: Date())
        routines.append(r)
        persistRoutines()
        return r
    }

    func updateRoutine(_ updated: Routine) {
        guard let i = routines.firstIndex(where: { $0.id == updated.id }) else { return }
        var r = updated
        r.updatedAt = Date()
        // Recalculate nextRun if schedule changed
        if r.schedule != routines[i].schedule {
            r.nextRun = Self.computeNextRun(for: r, after: Date())
        }
        routines[i] = r
        persistRoutines()
    }

    func deleteRoutine(id: String) {
        routines.removeAll { $0.id == id }
        persistRoutines()
    }

    func toggleEnabled(id: String) {
        guard let i = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[i].enabled   = !routines[i].enabled
        routines[i].updatedAt = Date()
        if routines[i].enabled && routines[i].nextRun == nil {
            routines[i].nextRun = Self.computeNextRun(for: routines[i], after: Date())
        }
        persistRoutines()
    }

    func logs(for routineId: String) -> [RoutineLog] {
        logs.filter { $0.routineId == routineId }
    }
}
