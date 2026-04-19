import SwiftUI

// MARK: - Activity View

struct ActivityView: View {
    @Environment(ActivityService.self)    private var activityService
    @Environment(FileWatcherService.self) private var watcher

    @State private var selectedCategory: ActivityCategory = .all
    @State private var actorFilter       = ""
    @State private var selectedEntry:    ActivityEntry?
    @State private var showPopover       = false
    @State private var watchToken:       WatchToken = -1

    private var filtered: [ActivityEntry] {
        activityService.filtered(
            category: selectedCategory,
            actor: actorFilter.isEmpty ? nil : actorFilter
        )
    }

    private var grouped: [(group: ActivityService.TimeGroup, entries: [ActivityEntry])] {
        activityService.grouped(entries: filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                feedContent
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem {
                Button {
                    activityService.load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            activityService.load()
            let path = NSHomeDirectory() + "/.claude/orchestrator/activity.jsonl"
            watchToken = watcher.watch(path) {
                activityService.load(limit: 500)
            }
        }
        .onDisappear { watcher.unwatch(watchToken) }
        .popover(isPresented: $showPopover) {
            if let entry = selectedEntry {
                ActivityDetailPopover(entry: entry)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ActivityCategory.allCases, id: \.self) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.horizontal, 16)
            }
            // Actor search + count
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter by agent...", text: $actorFilter)
                        .font(.callout)
                        .textFieldStyle(.plain)
                    if !actorFilter.isEmpty {
                        Button { actorFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

                Spacer()

                Text("\(filtered.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 16)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func categoryChip(_ cat: ActivityCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            selectedCategory = cat
        } label: {
            Text(cat.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.group) { group, groupEntries in
                    Section {
                        ForEach(groupEntries) { entry in
                            ActivityEntryRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id
                            )
                            .onTapGesture {
                                selectedEntry = entry
                                showPopover   = true
                            }
                            Divider().padding(.leading, 54)
                        }
                    } header: {
                        timeGroupHeader(group)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func timeGroupHeader(_ group: ActivityService.TimeGroup) -> some View {
        Text(group.rawValue)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(activityService.entries.isEmpty
                 ? "No activity yet\nEvents will appear here as agents and services run."
                 : "No events match this filter.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Activity Entry Row

struct ActivityEntryRow: View {
    let entry: ActivityEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type icon bubble
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: entry.type.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(typeColor)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                // Summary
                Text(entry.summary)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Actor + time
                HStack(spacing: 8) {
                    Label(entry.actor, systemImage: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(entry.timestamp.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if !entry.metadata.isEmpty {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Type badge
            Text(entry.type.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(typeColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(typeColor.opacity(0.1))
                .clipShape(Capsule())
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
    }

    private var typeColor: Color {
        switch entry.type.category {
        case .issues:    return .blue
        case .agents:    return .green
        case .approvals: return .orange
        case .costs:     return .purple
        case .routines:  return .cyan
        case .org:       return .pink
        case .tasks:     return Color(nsColor: .systemYellow)
        case .all:       return .secondary
        }
    }
}

// MARK: - Activity Detail Popover

struct ActivityDetailPopover: View {
    let entry: ActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: entry.type.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.type.label)
                        .font(.headline)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Summary
            Text(entry.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            // Actor
            Label(entry.actor, systemImage: "person.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Metadata
            if !entry.metadata.isEmpty {
                Divider()
                Text("Metadata")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entry.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        HStack(alignment: .top, spacing: 8) {
                            Text(k)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text(v)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Compact Activity Feed Widget (for OverviewView)

struct ActivityFeedWidget: View {
    let entries: [ActivityEntry]
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text("No recent activity.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries.prefix(6)) { entry in
                    compactRow(entry)
                    if entry.id != entries.prefix(6).last?.id {
                        Divider().padding(.leading, 28)
                    }
                }
            }

            Button {
                onViewAll()
            } label: {
                Label("View All Activity", systemImage: "arrow.right.circle")
                    .font(.callout)
                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    private func compactRow(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.62, green: 0.81, blue: 0.42))
                .frame(width: 18)

            Text(entry.summary)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                .lineLimit(1)

            Spacer()

            Text(entry.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.34, green: 0.37, blue: 0.55))
        }
        .padding(.vertical, 5)
    }
}
