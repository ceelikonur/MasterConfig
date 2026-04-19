import Foundation

// MARK: - Org Service

@Observable
@MainActor
final class OrgService {

    var nodes: [OrgNode] = []
    var isLoading = false

    private let fm = FileManager.default

    // MARK: - Paths

    private var orgDir:   String { NSHomeDirectory() + "/.claude/orchestrator/org" }
    private var nodesFile: String { orgDir + "/nodes.json" }

    // MARK: - Computed helpers

    var roots: [OrgNode] {
        nodes.filter { $0.reportsTo == nil }
             .sorted { $0.role.priority < $1.role.priority }
    }

    func children(of parentId: String) -> [OrgNode] {
        nodes.filter { $0.reportsTo == parentId }
             .sorted { $0.role.priority < $1.role.priority }
    }

    func node(id: String) -> OrgNode? {
        nodes.first { $0.id == id }
    }

    func parent(of node: OrgNode) -> OrgNode? {
        guard let pid = node.reportsTo else { return nil }
        return self.node(id: pid)
    }

    /// Returns the chain from root down to the given node (inclusive)
    func chain(for nodeId: String) -> [OrgNode] {
        var chain: [OrgNode] = []
        var current = node(id: nodeId)
        while let n = current {
            chain.insert(n, at: 0)
            current = n.reportsTo.flatMap { node(id: $0) }
        }
        return chain
    }

    // MARK: - Bootstrap

    func load() {
        isLoading = true
        defer { isLoading = false }
        ensureDirs()
        loadNodes()
    }

    private func ensureDirs() {
        try? fm.createDirectory(atPath: orgDir, withIntermediateDirectories: true)
    }

    private func loadNodes() {
        guard
            let data  = try? Data(contentsOf: URL(fileURLWithPath: nodesFile)),
            let items = try? JSONDecoder.iso.decode([OrgNode].self, from: data)
        else {
            nodes = []
            return
        }
        nodes = items.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Atomic Write

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

    private func persist() {
        guard let data = try? JSONEncoder.iso.encode(nodes) else { return }
        atomicWrite(data, to: nodesFile)
    }

    // MARK: - CRUD

    @discardableResult
    func addNode(
        agentName: String,
        role: OrgRole,
        title: String = "",
        reportsTo: String? = nil,
        team: String? = nil,
        responsibilities: [String] = [],
        skills: [String] = []
    ) -> OrgNode {
        let node = OrgNode(
            agentName: agentName, role: role, title: title,
            reportsTo: reportsTo, team: team,
            responsibilities: responsibilities, skills: skills
        )
        nodes.append(node)
        persist()
        return node
    }

    func updateNode(_ updated: OrgNode) {
        guard let idx = nodes.firstIndex(where: { $0.id == updated.id }) else { return }
        var n = updated
        n.updatedAt = Date()
        nodes[idx] = n
        persist()
    }

    func removeNode(id: String) {
        // Reparent children to removed node's parent
        let removed = node(id: id)
        let grandparent = removed?.reportsTo
        for i in nodes.indices where nodes[i].reportsTo == id {
            nodes[i].reportsTo = grandparent
        }
        nodes.removeAll { $0.id == id }
        persist()
    }

    func moveNode(id: String, newParent: String?) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[idx].reportsTo = newParent
        nodes[idx].updatedAt = Date()
        persist()
    }

    func setStatus(_ status: AgentOrgStatus, for id: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[idx].status = status
        nodes[idx].updatedAt = Date()
        persist()
    }
}
