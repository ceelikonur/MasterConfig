import SwiftUI

// MARK: - Export Sheet

struct ExportSheet: View {
    @Environment(ImportExportService.self) private var ieService
    @Binding var isPresented: Bool

    @State private var sectionItems: [ExportSectionItem] = []
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.doc")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Configuration")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Select which sections to include in the bundle")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(red: 0.35, green: 0.37, blue: 0.50))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Color(red: 0.18, green: 0.19, blue: 0.25))

            // Section checklist
            ScrollView {
                VStack(spacing: 0) {
                    // Select All / None row
                    HStack {
                        Button("Select All") {
                            for i in sectionItems.indices { sectionItems[i].isSelected = true }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                        Text("·").foregroundStyle(Color(red: 0.35, green: 0.37, blue: 0.50))
                        Button("Deselect All") {
                            for i in sectionItems.indices { sectionItems[i].isSelected = false }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                        Spacer()
                        Text("\(selectedCount) of \(sectionItems.count) selected")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    ForEach(sectionItems.indices, id: \.self) { i in
                        SectionCheckRow(item: $sectionItems[i])
                    }
                }
            }
            .frame(maxHeight: 340)

            Divider().background(Color(red: 0.18, green: 0.19, blue: 0.25))

            // Message
            if let msg = message ?? ieService.lastMessage {
                HStack {
                    Image(systemName: msg.contains("failed") || msg.contains("Failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(msg.contains("failed") || msg.contains("Failed") ? Color.orange : Color.green)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    let selected = Set(sectionItems.filter(\.isSelected).map(\.id))
                    ieService.exportToPanel(sections: selected)
                    if ieService.lastMessage?.contains("→") == true {
                        message = ieService.lastMessage
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isPresented = false }
                    } else {
                        message = ieService.lastMessage
                    }
                } label: {
                    Label("Export", systemImage: "arrow.up.doc")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedCount == 0 || ieService.isExporting)
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Color(red: 0.10, green: 0.11, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { sectionItems = ieService.currentSectionItems() }
    }

    private var selectedCount: Int { sectionItems.filter(\.isSelected).count }
}

// MARK: - Section Check Row

private struct SectionCheckRow: View {
    @Binding var item: ExportSectionItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                .frame(width: 18)

            Text(item.label)
                .font(.system(.body, design: .default))
                .foregroundStyle(.white)

            Spacer()

            if item.count > 0 {
                Text("\(item.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.18, green: 0.19, blue: 0.25))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(item.isSelected ? Color(red: 0.14, green: 0.15, blue: 0.20) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { item.isSelected.toggle() }
    }
}

// MARK: - Import Preview Sheet

struct ImportPreviewSheet: View {
    @Environment(ImportExportService.self) private var ieService
    @Binding var isPresented: Bool
    let export: MasterConfigExport

    @State private var preview: ImportPreview = ImportPreview(version: "", exportDate: Date(), appVersion: "")
    @State private var selectedSections: Set<String> = ["hierarchy", "org", "budgets", "routines", "governance", "skills", "agents", "mcp"]
    @State private var conflicts: [ImportConflict] = []
    @State private var isApplying = false
    @State private var doneMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.down.doc")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Preview")
                        .font(.headline).foregroundStyle(.white)
                    Text("v\(preview.version) · exported \(preview.exportDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(red: 0.35, green: 0.37, blue: 0.50))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Color(red: 0.18, green: 0.19, blue: 0.25))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary counts
                    sectionSummary

                    // Conflict list
                    if !conflicts.isEmpty {
                        conflictSection
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 400)

            Divider().background(Color(red: 0.18, green: 0.19, blue: 0.25))

            // Done message
            if let msg = doneMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg).font(.caption).foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.97))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    isApplying = true
                    Task {
                        await ieService.applyImport(export: export, selectedSections: selectedSections, conflicts: conflicts)
                        doneMessage = ieService.lastMessage
                        isApplying = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { isPresented = false }
                    }
                } label: {
                    if isApplying {
                        HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Importing...") }
                    } else {
                        Label("Import Selected", systemImage: "arrow.down.doc")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isApplying || selectedSections.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520)
        .background(Color(red: 0.10, green: 0.11, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            preview   = ieService.preview(export)
            conflicts = preview.conflicts
        }
    }

    // MARK: - Summary Grid

    private var sectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contents")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                .textCase(.uppercase)

            let rows: [(id: String, icon: String, label: String, count: Int)] = [
                ("hierarchy", "checklist",              "Goals, Projects & Issues",  preview.goalCount + preview.projectCount + preview.issueCount),
                ("org",       "person.3",               "Org Nodes",                 preview.orgNodeCount),
                ("budgets",   "dollarsign.circle",      "Budget Configs",            preview.budgetCount),
                ("routines",  "repeat",                 "Routines",                  preview.routineCount),
                ("governance","shield",                 "Governance Config",         preview.approvalCount > 0 ? 1 + preview.approvalCount : 1),
                ("skills",    "book.closed",            "Skills",                    preview.skillCount),
                ("agents",    "person.crop.rectangle", "Agent Definitions",         preview.agentCount),
                ("mcp",       "server.rack",            "MCP Servers",              preview.mcpServerCount),
            ]

            ForEach(rows, id: \.id) { row in
                if row.count > 0 {
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { selectedSections.contains(row.id) },
                            set: { if $0 { selectedSections.insert(row.id) } else { selectedSections.remove(row.id) } }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Image(systemName: row.icon)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                            .frame(width: 16)
                        Text(row.label)
                            .font(.body)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(row.count) item\(row.count == 1 ? "" : "s")")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(red: 0.18, green: 0.19, blue: 0.25))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 6)
                }
            }

            Text("Total: \(preview.totalCount) items")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color(red: 0.48, green: 0.64, blue: 0.97))
                .padding(.top, 4)
        }
    }

    // MARK: - Conflict Section

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text("\(conflicts.count) Conflict\(conflicts.count == 1 ? "" : "s") Detected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }

            ForEach(conflicts.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflicts[i].itemName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(conflicts[i].section)
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.60))
                    }
                    Spacer()
                    Picker("", selection: $conflicts[i].resolution) {
                        ForEach(ConflictResolution.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(red: 0.14, green: 0.15, blue: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Shared Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default).weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(red: 0.34, green: 0.50, blue: 0.92).opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default))
            .foregroundStyle(Color(red: 0.65, green: 0.68, blue: 0.80))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(red: 0.18, green: 0.19, blue: 0.25).opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
