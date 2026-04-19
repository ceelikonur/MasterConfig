import SwiftUI

// MARK: - Main View

struct RoutinesView: View {
    @Environment(RoutineService.self)     private var routineService
    @Environment(HierarchyService.self)  private var hierarchyService

    @State private var selectedId:  String?
    @State private var showAddSheet = false
    @State private var filterEnabled: Bool? = nil   // nil=all, true=enabled, false=disabled

    private var filtered: [Routine] {
        let r = routineService.routines
        switch filterEnabled {
        case .some(true):  return r.filter {  $0.enabled }
        case .some(false): return r.filter { !$0.enabled }
        default:           return r
        }
    }

    var body: some View {
        HSplitView {
            // ── Left: routine list ──
            routineList
                .frame(minWidth: 280, maxWidth: 380)

            // ── Right: detail panel ──
            Group {
                if let id = selectedId,
                   let routine = routineService.routines.first(where: { $0.id == id }) {
                    RoutineDetailPanel(
                        routine: routine,
                        routineService: routineService,
                        hierarchyService: hierarchyService,
                        onDelete: {
                            selectedId = nil
                            routineService.deleteRoutine(id: id)
                        }
                    )
                } else {
                    routineEmptyState
                }
            }
            .frame(minWidth: 360)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showAddSheet = true
                } label: {
                    Label("New Routine", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRoutineSheet(
                routineService: routineService,
                hierarchyService: hierarchyService
            )
        }
        .onAppear { routineService.load() }
        .navigationTitle("Routines")
    }

    // MARK: - Routine List

    private var routineList: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 6) {
                filterButton(label: "All",     value: nil)
                filterButton(label: "Enabled", value: true)
                filterButton(label: "Disabled", value: false)
                Spacer()
                Text("\(filtered.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(routineService.routines.isEmpty
                         ? "No routines yet\nClick + to create one"
                         : "No routines match this filter")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selectedId) { routine in
                    RoutineRow(routine: routine, routineService: routineService)
                        .tag(routine.id)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func filterButton(label: String, value: Bool?) -> some View {
        Button {
            filterEnabled = value
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(filterEnabled == value ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(filterEnabled == value ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    filterEnabled == value ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2),
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var routineEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Recurring Automation")
                    .font(.headline)
                Text("Routines auto-create issues on a schedule.\nSelect a routine to see details, or click + to create one.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Routine Row

private struct RoutineRow: View {
    let routine: Routine
    let routineService: RoutineService

    var body: some View {
        HStack(spacing: 10) {
            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { routine.enabled },
                set: { _ in routineService.toggleEnabled(id: routine.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            // Schedule icon
            Image(systemName: routine.schedule.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(routine.enabled ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(routine.enabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(routine.schedule.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if routine.runCount > 0 {
                    Text("\(routine.runCount)×")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if routine.enabled, let next = routine.nextRun {
                    Text(nextRunLabel(next))
                        .font(.caption2)
                        .foregroundStyle(isOverdue(next) ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func nextRunLabel(_ date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        if delta < 0      { return "overdue" }
        if delta < 60     { return "< 1m" }
        if delta < 3600   { return "in \(Int(delta / 60))m" }
        if delta < 86400  { return "in \(Int(delta / 3600))h" }
        return "in \(Int(delta / 86400))d"
    }

    private func isOverdue(_ date: Date) -> Bool { date < Date() }
}

// MARK: - Routine Detail Panel

struct RoutineDetailPanel: View {
    let routine: Routine
    let routineService: RoutineService
    let hierarchyService: HierarchyService
    let onDelete: () -> Void

    @State private var isEditing   = false
    @State private var showConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                if isEditing {
                    RoutineEditForm(
                        routine: routine,
                        routineService: routineService,
                        hierarchyService: hierarchyService,
                        onCancel: { isEditing = false },
                        onSave:   { isEditing = false }
                    )
                } else {
                    infoSection
                    Divider().padding(.vertical, 4)
                    actionButtons
                    Divider().padding(.vertical, 4)
                    logSection
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("Delete \"\(routine.title)\"?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete the routine and its schedule. Existing issues are not affected.")
        }
        .onChange(of: routine.id) { _, _ in isEditing = false }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(routine.enabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: routine.schedule.type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(routine.enabled ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    statusBadge
                    Text(routine.schedule.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(routine.enabled ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(routine.enabled ? "Enabled" : "Disabled")
                .font(.caption2.bold())
                .foregroundStyle(routine.enabled ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((routine.enabled ? Color.green : Color.secondary).opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !routine.description.isEmpty {
                Text(routine.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            Group {
                infoRow("Schedule",  routine.schedule.summary,    "calendar.badge.clock")
                if let a = routine.assignee, !a.isEmpty {
                    infoRow("Assignee", a, "person.circle")
                }
                infoRow("Run count", "\(routine.runCount) times", "repeat")
                if let last = routine.lastRun {
                    infoRow("Last run", last.formatted(.relative(presentation: .named)), "clock.arrow.circlepath")
                }
                if let next = routine.nextRun {
                    infoRow("Next run",
                            next.formatted(date: .abbreviated, time: .shortened),
                            "clock.badge.exclamationmark",
                            accent: next < Date())
                }
            }

            // Issue template preview
            VStack(alignment: .leading, spacing: 6) {
                Label("Issue Template", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 4) {
                    let tpl = routine.issueTemplate
                    let title = tpl.title.isEmpty ? routine.title : tpl.title
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    if !tpl.description.isEmpty {
                        Text(tpl.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        priorityBadge(tpl.priority)
                        if let pid = tpl.projectId,
                           let proj = hierarchyService.projects.first(where: { $0.id == pid }) {
                            Text(proj.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(tpl.labels.prefix(3), id: \.self) { lbl in
                            Text(lbl)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    private func infoRow(_ label: String, _ value: String, _ icon: String, accent: Bool = false) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(accent ? Color.red : Color.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func priorityBadge(_ p: IssuePriority) -> some View {
        let (color, label): (Color, String) = {
            switch p {
            case .low:    return (.secondary, "Low")
            case .normal: return (.blue, "Normal")
            case .high:   return (.orange, "High")
            case .urgent: return (.red, "Urgent")
            }
        }()
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    routineService.toggleEnabled(id: routine.id)
                } label: {
                    Label(routine.enabled ? "Disable" : "Enable",
                          systemImage: routine.enabled ? "pause.circle" : "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    routineService.triggerNow(id: routine.id)
                } label: {
                    Label("Run Now", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Trigger this routine immediately, creating an issue now.")
            }

            HStack(spacing: 8) {
                Button { isEditing = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Log Section

    private var logSection: some View {
        let routineLogs = routineService.logs(for: routine.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Run History", systemImage: "list.bullet.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(routineLogs.count) runs")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)

            if routineLogs.isEmpty {
                Text("No runs yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            } else {
                ForEach(routineLogs.prefix(20)) { log in
                    logRow(log)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func logRow(_ log: RoutineLog) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(log.success ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                if let title = log.issueTitle {
                    Text(title)
                        .font(.caption)
                        .lineLimit(1)
                } else if let err = log.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Text(log.firedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if log.success {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }
}

// MARK: - Routine Edit Form (inline)

struct RoutineEditForm: View {
    let routine: Routine
    let routineService: RoutineService
    let hierarchyService: HierarchyService
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var title        = ""
    @State private var description  = ""
    @State private var assignee     = ""
    @State private var schedType    = ScheduleType.daily
    @State private var intervalMins = 60
    @State private var timeOfDay    = "09:00"
    @State private var weekday      = 1
    @State private var dayOfMonth   = 1
    @State private var tplTitle     = ""
    @State private var tplDesc      = ""
    @State private var tplPriority  = IssuePriority.normal
    @State private var tplLabels    = ""
    @State private var tplProjectId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Routine") {
                    TextField("Title (required)", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Assignee agent name", text: $assignee)
                }

                Section("Schedule") {
                    Picker("Type", selection: $schedType) {
                        ForEach(ScheduleType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }

                    switch schedType {
                    case .interval:
                        Stepper(
                            "Every \(intervalMins) minutes",
                            value: $intervalMins,
                            in: 5...10080,
                            step: intervalMins < 60 ? 5 : (intervalMins < 1440 ? 30 : 60)
                        )
                    case .daily:
                        timeOfDayField
                    case .weekly:
                        weekdayPicker
                        timeOfDayField
                    case .monthly:
                        dayOfMonthPicker
                        timeOfDayField
                    }
                }

                Section("Issue Template") {
                    TextField("Issue title (defaults to routine title)", text: $tplTitle)
                    TextField("Description", text: $tplDesc, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Priority", selection: $tplPriority) {
                        ForEach(IssuePriority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    TextField("Labels (comma-separated)", text: $tplLabels)
                    Picker("Project", selection: $tplProjectId) {
                        Text("None").tag(String?.none)
                        ForEach(hierarchyService.projects) { p in
                            Text(p.title).tag(String?.some(p.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Save") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .onAppear { populateFields() }
    }

    private var timeOfDayField: some View {
        HStack {
            Text("Time of day")
            Spacer()
            TextField("HH:MM", text: $timeOfDay)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
        }
    }

    private var weekdayPicker: some View {
        let days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        return Picker("Day of week", selection: $weekday) {
            ForEach(0..<7, id: \.self) { i in
                Text(days[i]).tag(i)
            }
        }
    }

    private var dayOfMonthPicker: some View {
        Picker("Day of month", selection: $dayOfMonth) {
            ForEach(1...28, id: \.self) { d in
                Text("Day \(d)").tag(d)
            }
        }
    }

    private func populateFields() {
        title       = routine.title
        description = routine.description
        assignee    = routine.assignee ?? ""
        schedType   = routine.schedule.type
        intervalMins = routine.schedule.intervalMinutes ?? 60
        timeOfDay   = routine.schedule.timeOfDay ?? "09:00"
        weekday     = routine.schedule.weekday ?? 1
        dayOfMonth  = routine.schedule.dayOfMonth ?? 1
        let tpl     = routine.issueTemplate
        tplTitle    = tpl.title
        tplDesc     = tpl.description
        tplPriority = tpl.priority
        tplLabels   = tpl.labels.joined(separator: ", ")
        tplProjectId = tpl.projectId
    }

    private func saveChanges() {
        var updated = routine
        updated.title       = title.trimmingCharacters(in: .whitespaces)
        updated.description = description.trimmingCharacters(in: .whitespaces)
        updated.assignee    = assignee.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                              : assignee.trimmingCharacters(in: .whitespaces)
        updated.schedule    = RoutineSchedule(
            type: schedType,
            intervalMinutes: schedType == .interval ? intervalMins : nil,
            timeOfDay:       schedType != .interval ? timeOfDay : nil,
            weekday:         schedType == .weekly   ? weekday   : nil,
            dayOfMonth:      schedType == .monthly  ? dayOfMonth : nil
        )
        updated.issueTemplate = IssueTemplate(
            title:       tplTitle.trimmingCharacters(in: .whitespaces),
            description: tplDesc.trimmingCharacters(in: .whitespaces),
            priority:    tplPriority,
            labels:      tplLabels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            projectId:   tplProjectId
        )
        routineService.updateRoutine(updated)
        onSave()
    }
}

// MARK: - Add Routine Sheet

struct AddRoutineSheet: View {
    let routineService: RoutineService
    let hierarchyService: HierarchyService
    @Environment(\.dismiss) private var dismiss

    @State private var title        = ""
    @State private var description  = ""
    @State private var assignee     = ""
    @State private var schedType    = ScheduleType.daily
    @State private var intervalMins = 60
    @State private var timeOfDay    = "09:00"
    @State private var weekday      = 1
    @State private var dayOfMonth   = 1
    @State private var tplTitle     = ""
    @State private var tplDesc      = ""
    @State private var tplPriority  = IssuePriority.normal
    @State private var tplLabels    = ""
    @State private var tplProjectId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("New Routine", systemImage: "clock.arrow.2.circlepath")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                Section("Routine") {
                    TextField("Title (required)", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Assignee", text: $assignee)
                }

                Section("Schedule") {
                    Picker("Type", selection: $schedType) {
                        ForEach(ScheduleType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    switch schedType {
                    case .interval:
                        Stepper("Every \(intervalMins) min",
                                value: $intervalMins, in: 5...10080, step: 15)
                    case .daily:
                        HStack {
                            Text("Time"); Spacer()
                            TextField("09:00", text: $timeOfDay)
                                .frame(width: 60).textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                    case .weekly:
                        Picker("Day", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { i in
                                Text(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][i]).tag(i)
                            }
                        }
                        HStack {
                            Text("Time"); Spacer()
                            TextField("09:00", text: $timeOfDay)
                                .frame(width: 60).textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                    case .monthly:
                        Picker("Day of month", selection: $dayOfMonth) {
                            ForEach(1...28, id: \.self) { Text("Day \($0)").tag($0) }
                        }
                        HStack {
                            Text("Time"); Spacer()
                            TextField("09:00", text: $timeOfDay)
                                .frame(width: 60).textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                Section("Issue Template") {
                    TextField("Issue title (defaults to routine title)", text: $tplTitle)
                    TextField("Description", text: $tplDesc, axis: .vertical)
                        .lineLimit(2...3)
                    Picker("Priority", selection: $tplPriority) {
                        ForEach(IssuePriority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    TextField("Labels (comma-separated)", text: $tplLabels)
                    Picker("Project", selection: $tplProjectId) {
                        Text("None").tag(String?.none)
                        ForEach(hierarchyService.projects) { p in
                            Text(p.title).tag(String?.some(p.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(schedulePreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Create Routine") {
                    createRoutine()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 460, height: 580)
    }

    private var schedulePreview: String {
        let mock = Routine(title: title, schedule: RoutineSchedule(
            type: schedType,
            intervalMinutes: schedType == .interval ? intervalMins : nil,
            timeOfDay: schedType != .interval ? timeOfDay : nil,
            weekday: schedType == .weekly ? weekday : nil,
            dayOfMonth: schedType == .monthly ? dayOfMonth : nil
        ))
        let next = RoutineService.computeNextRun(for: mock)
        return "First run: \(next.formatted(date: .abbreviated, time: .shortened))"
    }

    private func createRoutine() {
        let sched = RoutineSchedule(
            type: schedType,
            intervalMinutes: schedType == .interval ? intervalMins : nil,
            timeOfDay: schedType != .interval ? timeOfDay : nil,
            weekday: schedType == .weekly ? weekday : nil,
            dayOfMonth: schedType == .monthly ? dayOfMonth : nil
        )
        let tpl = IssueTemplate(
            title: tplTitle.trimmingCharacters(in: .whitespaces),
            description: tplDesc.trimmingCharacters(in: .whitespaces),
            priority: tplPriority,
            labels: tplLabels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            projectId: tplProjectId
        )
        routineService.addRoutine(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            assignee: assignee.isEmpty ? nil : assignee.trimmingCharacters(in: .whitespaces),
            schedule: sched,
            issueTemplate: tpl
        )
    }
}
