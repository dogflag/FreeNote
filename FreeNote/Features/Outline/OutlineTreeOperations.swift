import Foundation

struct OutlineFlatRow: Identifiable {
    let node: OutlineNode
    let depth: Int
    let parentID: UUID?

    var id: UUID { node.id }
}

enum OutlineTreeOperations {
    struct SiblingLocation {
        let parentID: UUID?
        let index: Int
    }

    static func flatten(nodes: [OutlineNode], expanded: Set<UUID>) -> [OutlineFlatRow] {
        var result: [OutlineFlatRow] = []
        var stack: [(OutlineNode, Int, UUID?)] = nodes.reversed().map { ($0, 0, nil) }
        var visited = Set<UUID>()

        while let (node, depth, parentID) = stack.popLast() {
            guard depth <= OutlineEditor.maximumDepth else { continue }
            guard visited.insert(node.id).inserted else { continue }
            result.append(OutlineFlatRow(node: node, depth: depth, parentID: parentID))
            if expanded.contains(node.id), depth < OutlineEditor.maximumDepth {
                for child in node.children.reversed() {
                    stack.append((child, depth + 1, node.id))
                }
            }
        }
        return result
    }

    static func allIDs(in nodes: [OutlineNode]) -> Set<UUID> {
        var ids = Set<UUID>()
        var stack = nodes
        var depth = 0
        while !stack.isEmpty && depth <= OutlineEditor.maximumDepth {
            let current = stack
            stack.removeAll(keepingCapacity: true)
            for node in current {
                guard ids.insert(node.id).inserted else { continue }
                stack.append(contentsOf: node.children)
            }
            depth += 1
        }
        return ids
    }

    static func node(id: UUID, in nodes: [OutlineNode]) -> OutlineNode? {
        var stack = nodes
        var visited = Set<UUID>()
        var depth = 0
        while !stack.isEmpty && depth <= OutlineEditor.maximumDepth {
            let current = stack
            stack.removeAll(keepingCapacity: true)
            for node in current {
                guard visited.insert(node.id).inserted else { continue }
                if node.id == id { return node }
                stack.append(contentsOf: node.children)
            }
            depth += 1
        }
        return nil
    }

    static func updateNode(id: UUID, in nodes: inout [OutlineNode], transform: (inout OutlineNode) -> Void, depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            transform(&nodes[index])
            return true
        }
        for index in nodes.indices {
            if updateNode(id: id, in: &nodes[index].children, transform: transform, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    static func addRoot(to nodes: inout [OutlineNode], page: Int, pageCount: Int) {
        let bounded = boundedPage(page, pageCount: pageCount)
        nodes.append(OutlineNode(title: "新大纲节点", startPage: bounded, endPage: bounded))
    }

    static func addChild(to parentID: UUID, in nodes: inout [OutlineNode], page: Int, pageCount: Int) -> UUID? {
        let bounded = boundedPage(page, pageCount: pageCount)
        let child = OutlineNode(title: "新子节点", startPage: bounded, endPage: bounded)
        let added = updateNode(id: parentID, in: &nodes, depth: 0) { node in
            node.children.append(child)
        }
        return added ? child.id : nil
    }

    static func addSibling(after id: UUID?, in nodes: inout [OutlineNode], page: Int, pageCount: Int) -> UUID? {
        let bounded = boundedPage(page, pageCount: pageCount)
        let newNode = OutlineNode(title: "新大纲节点", startPage: bounded, endPage: bounded)
        guard let id else {
            nodes.append(newNode)
            return newNode.id
        }
        guard let location = locateSibling(id: id, in: nodes) else { return nil }
        return insert(newNode, parentID: location.parentID, at: location.index + 1, in: &nodes) ? newNode.id : nil
    }

    static func remove(id: UUID, in nodes: inout [OutlineNode], depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes.remove(at: index)
            return true
        }
        for index in nodes.indices {
            if remove(id: id, in: &nodes[index].children, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    static func moveSibling(id: UUID, offset: Int, in nodes: inout [OutlineNode], depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            let target = index + offset
            guard nodes.indices.contains(target) else { return false }
            nodes.swapAt(index, target)
            return true
        }
        for index in nodes.indices {
            if moveSibling(id: id, offset: offset, in: &nodes[index].children, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    static func indent(id: UUID, in nodes: inout [OutlineNode], depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            guard index > 0 else { return false }
            let moving = nodes.remove(at: index)
            nodes[index - 1].children.append(moving)
            return true
        }
        for index in nodes.indices {
            if indent(id: id, in: &nodes[index].children, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    static func outdent(id: UUID, in nodes: inout [OutlineNode], depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        guard let parentID = parentID(of: id, in: nodes) else { return false }
        guard let parentLocation = locateSibling(id: parentID, in: nodes) else { return false }
        guard let moving = node(id: id, in: nodes) else { return false }
        guard remove(id: id, in: &nodes) else { return false }
        return insert(moving, parentID: parentLocation.parentID, at: parentLocation.index + 1, in: &nodes)
    }

    static func parentID(of id: UUID, in nodes: [OutlineNode]) -> UUID? {
        func search(_ list: [OutlineNode], parent: UUID?, depth: Int) -> UUID? {
            guard depth <= OutlineEditor.maximumDepth else { return nil }
            for node in list {
                if node.id == id { return parent }
                if let found = search(node.children, parent: node.id, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }
        if nodes.contains(where: { $0.id == id }) { return nil }
        return search(nodes, parent: nil, depth: 0)
    }

    private static func locateSibling(id: UUID, in nodes: [OutlineNode], parentID: UUID? = nil, depth: Int = 0) -> SiblingLocation? {
        guard depth <= OutlineEditor.maximumDepth else { return nil }
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            return SiblingLocation(parentID: parentID, index: index)
        }
        for node in nodes {
            if let location = locateSibling(id: id, in: node.children, parentID: node.id, depth: depth + 1) {
                return location
            }
        }
        return nil
    }

    @discardableResult
    private static func insert(_ node: OutlineNode, parentID: UUID?, at index: Int, in nodes: inout [OutlineNode], depth: Int = 0) -> Bool {
        guard depth <= OutlineEditor.maximumDepth else { return false }
        if let parentID {
            guard let parentIndex = nodes.firstIndex(where: { $0.id == parentID }) else {
                for childIndex in nodes.indices {
                    if insert(node, parentID: parentID, at: index, in: &nodes[childIndex].children, depth: depth + 1) {
                        return true
                    }
                }
                return false
            }
            let safeIndex = min(max(index, 0), nodes[parentIndex].children.count)
            nodes[parentIndex].children.insert(node, at: safeIndex)
            return true
        }

        // A nil parent is only valid at the true root level.
        let safeIndex = min(max(index, 0), nodes.count)
        nodes.insert(node, at: safeIndex)
        return true
    }

    static func boundedPage(_ value: Int, pageCount: Int) -> Int {
        min(max(value, 1), max(pageCount, 1))
    }
}
