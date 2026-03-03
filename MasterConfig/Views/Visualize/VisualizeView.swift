import SwiftUI
import AppKit

struct VisualizeView: View {
    @Environment(ClaudeService.self) private var claudeService

    @State private var diagramElements: String = "[]"
    @State private var showSaveAlert = false
    @State private var isReadOnly = false

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.11, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Toolbar
                HStack(spacing: 12) {
                    Text("Visualize")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))

                    Spacer()

                    Button {
                        diagramElements = buildDiagram()
                    } label: {
                        Label("Generate Diagram", systemImage: "wand.and.stars")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.48, green: 0.64, blue: 0.97))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        diagramElements = "[]"
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSaveAlert = true
                    } label: {
                        Label("Save as PNG", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        exportDiagram()
                    } label: {
                        Label("Export .excalidraw", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isReadOnly.toggle()
                    } label: {
                        Label(isReadOnly ? "Edit" : "View", systemImage: isReadOnly ? "pencil" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.75, green: 0.80, blue: 0.97))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.13, green: 0.14, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.34, green: 0.37, blue: 0.55).opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(red: 0.13, green: 0.14, blue: 0.18))

                // MARK: - Excalidraw Canvas
                ExcalidrawView(elements: $diagramElements, isReadOnly: isReadOnly)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Save as PNG", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("PNG export is not yet implemented.")
        }
        .animation(.easeInOut(duration: 0.15), value: diagramElements)
    }

    // MARK: - Export

    private func exportDiagram() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "claude-config.excalidraw"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let wrapper = """
            {"type":"excalidraw","version":2,"source":"MasterConfig","elements":\(diagramElements),"appState":{"gridSize":null,"viewBackgroundColor":"#1a1b26"}}
            """
            try? wrapper.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Diagram Builder

    private func buildDiagram() -> String {
        var elements: [[String: Any]] = []
        let centerX = 400.0
        let centerY = 300.0

        // Central node
        let centerId = UUID().uuidString
        elements.append(makeRect(
            id: centerId, x: centerX, y: centerY,
            width: 160, height: 60,
            text: "Claude Config",
            bgColor: "#7aa2f7", strokeColor: "#7aa2f7"
        ))

        // Skills — left column
        let skills = claudeService.skills
        let skillStartY = centerY - Double(skills.count - 1) * 40
        for (i, skill) in skills.enumerated() {
            let nodeId = UUID().uuidString
            let x = centerX - 280
            let y = skillStartY + Double(i) * 80
            elements.append(makeRect(
                id: nodeId, x: x, y: y,
                width: 140, height: 50,
                text: skill.name,
                bgColor: "#7aa2f7", strokeColor: "#7aa2f7"
            ))
            elements.append(makeArrow(
                fromId: nodeId, toId: centerId,
                fromX: x + 140, fromY: y + 25,
                toX: centerX, toY: centerY + 30
            ))
        }

        // Agents — right column
        let agents = claudeService.agents
        let agentStartY = centerY - Double(agents.count - 1) * 40
        for (i, agent) in agents.enumerated() {
            let nodeId = UUID().uuidString
            let x = centerX + 280
            let y = agentStartY + Double(i) * 80
            let label = "\(agent.name)\n[\(agent.model)]"
            elements.append(makeRect(
                id: nodeId, x: x, y: y,
                width: 160, height: 55,
                text: label,
                bgColor: "#9ece6a", strokeColor: "#9ece6a"
            ))
            elements.append(makeArrow(
                fromId: centerId, toId: nodeId,
                fromX: centerX + 160, fromY: centerY + 30,
                toX: x, toY: y + 27
            ))
        }

        // MCP Servers — below center
        let servers = claudeService.mcpServers
        let serverStartX = centerX - Double(servers.count - 1) * 90
        for (i, server) in servers.enumerated() {
            let nodeId = UUID().uuidString
            let x = serverStartX + Double(i) * 180
            let y = centerY + 160
            elements.append(makeRect(
                id: nodeId, x: x, y: y,
                width: 150, height: 50,
                text: server.name,
                bgColor: "#ff9e64", strokeColor: "#ff9e64"
            ))
            elements.append(makeArrow(
                fromId: centerId, toId: nodeId,
                fromX: centerX + 80, fromY: centerY + 60,
                toX: x + 75, toY: y
            ))
        }

        guard let data = try? JSONSerialization.data(withJSONObject: elements, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func makeRect(id: String, x: Double, y: Double, width: Double, height: Double, text: String, bgColor: String, strokeColor: String) -> [String: Any] {
        [
            "type": "rectangle",
            "id": id,
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "text": text,
            "backgroundColor": bgColor,
            "strokeColor": strokeColor,
            "fillStyle": "solid",
            "roughness": 1,
            "strokeWidth": 2,
            "fontSize": 14,
            "fontFamily": 1,
            "textAlign": "center",
            "verticalAlign": "middle",
            "seed": Int.random(in: 1...999999)
        ] as [String: Any]
    }

    private func makeArrow(fromId: String, toId: String, fromX: Double, fromY: Double, toX: Double, toY: Double) -> [String: Any] {
        [
            "type": "arrow",
            "id": UUID().uuidString,
            "x": fromX,
            "y": fromY,
            "width": toX - fromX,
            "height": toY - fromY,
            "strokeColor": "#565f89",
            "strokeWidth": 2,
            "roughness": 1,
            "points": [[0, 0], [toX - fromX, toY - fromY]],
            "startBinding": ["elementId": fromId, "focus": 0, "gap": 4],
            "endBinding": ["elementId": toId, "focus": 0, "gap": 4],
            "seed": Int.random(in: 1...999999)
        ] as [String: Any]
    }
}
