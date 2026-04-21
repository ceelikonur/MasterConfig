import SwiftUI

// MARK: - Main View

struct FleetView: View {
    @Environment(FleetService.self) private var fleetService

    @State private var selectedId: String?
    @State private var showAddSheet = false
    @State private var isRefreshing = false

    var body: some View {
        HSplitView {
            listPanel
                .frame(minWidth: 300, maxWidth: 420)

            Group {
                if let id = selectedId,
                   fleetService.projects.contains(where: { $0.id == id }) {
                    FleetProjectDetailView(
                        projectId: id,
                        onRemoved: { selectedId = nil }
                    )
                } else {
                    detailEmptyState
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        isRefreshing = true
                        await fleetService.refreshAllHealth()
                        isRefreshing = false
                    }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise.circle")
                }
                .disabled(fleetService.projects.isEmpty || isRefreshing)
                .help("Refresh health for all projects")

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus.circle")
                }
                .help("Add a new project")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            FleetAddProjectSheet()
        }
        .onAppear { fleetService.load() }
        .navigationTitle("Fleet")
    }

    // MARK: - List Panel

    private var listPanel: some View {
        Group {
            if fleetService.projects.isEmpty {
                listEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(fleetService.projects) { project in
                            FleetProjectCard(
                                project: project,
                                isSelected: selectedId == project.id
                            )
                            .onTapGesture {
                                selectedId = project.id
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Empty States

    private var listEmptyState: some View {
        ContentUnavailableView {
            Label("No Projects Yet", systemImage: "shippingbox.and.arrow.backward")
        } description: {
            Text("Track GitHub, Supabase, and Netlify health across your client projects in one place.")
        } actions: {
            Button {
                showAddSheet = true
            } label: {
                Label("Add First Project", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Select a project\nto see health details")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Project Card

private struct FleetProjectCard: View {
    let project: FleetProject
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FleetHealthBadge(
                status: project.lastHealth?.status,
                score: project.lastHealth?.score,
                size: .small
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let client = project.clientName, !client.isEmpty {
                        Text(client)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 5) {
                    integrationChip(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "GitHub",
                        configured: project.github != nil,
                        color: .purple
                    )
                    integrationChip(
                        icon: "cylinder.split.1x2",
                        label: "Supabase",
                        configured: project.supabase != nil,
                        color: .green
                    )
                    integrationChip(
                        icon: "globe",
                        label: "Netlify",
                        configured: project.netlify != nil,
                        color: .cyan
                    )
                }

                if let checked = project.lastCheckedAt {
                    Text("Checked \(checked.formatted(.relative(presentation: .numeric)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not yet checked")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
    }

    private func integrationChip(icon: String, label: String, configured: Bool, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((configured ? color : Color.secondary).opacity(0.14))
        )
        .foregroundStyle(configured ? color : Color.secondary)
    }
}
