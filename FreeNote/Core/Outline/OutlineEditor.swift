import Foundation

enum OutlineEditor {
    /// Defensive limit for corrupted data. Normal user outlines do not approach this depth.
    static let maximumDepth = 512

    static func validate(_ nodes: [OutlineNode], pageCount: Int? = nil) throws {
        var seenIDs = Set<UUID>()
        var stack: [(node: OutlineNode, depth: Int)] = nodes.reversed().map { ($0, 1) }

        while let entry = stack.popLast() {
            let node = entry.node
            if entry.depth > maximumDepth {
                throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
            }
            guard seenIDs.insert(node.id).inserted else {
                throw FreeNoteError.duplicateOutlineNodeID(node.id)
            }
            guard node.startPage >= 1, node.endPage >= node.startPage else {
                throw FreeNoteError.invalidOutlineRange(
                    nodeID: node.id,
                    startPage: node.startPage,
                    endPage: node.endPage
                )
            }
            if let pageCount, node.startPage > pageCount || node.endPage > pageCount {
                throw FreeNoteError.outlinePageOutOfBounds(
                    nodeID: node.id,
                    startPage: node.startPage,
                    endPage: node.endPage,
                    pageCount: pageCount
                )
            }
            if !node.children.isEmpty {
                stack.append(contentsOf: node.children.reversed().map { ($0, entry.depth + 1) })
            }
        }
    }

    static func findNode(id: UUID, in nodes: [OutlineNode]) -> OutlineNode? {
        path(to: id, in: nodes)?.last
    }

    static func path(to id: UUID, in nodes: [OutlineNode]) -> [OutlineNode]? {
        var stack: [(node: OutlineNode, path: [OutlineNode])] = nodes.reversed().map { ($0, [$0]) }
        while let entry = stack.popLast() {
            if entry.path.count > maximumDepth {
                return nil
            }
            if entry.node.id == id {
                return entry.path
            }
            if !entry.node.children.isEmpty {
                stack.append(contentsOf: entry.node.children.reversed().map {
                    ($0, entry.path + [$0])
                })
            }
        }
        return nil
    }

    static func parentID(of id: UUID, in nodes: [OutlineNode]) -> UUID? {
        guard let path = path(to: id, in: nodes), path.count > 1 else {
            return nil
        }
        return path[path.count - 2].id
    }

    static func subtreeIDs(of id: UUID, in nodes: [OutlineNode]) -> Set<UUID> {
        guard let root = findNode(id: id, in: nodes) else {
            return []
        }
        var result = Set<UUID>()
        var stack = [root]
        while let node = stack.popLast() {
            result.insert(node.id)
            stack.append(contentsOf: node.children)
        }
        return result
    }

    static func addRoot(
        title: String,
        startPage: Int,
        endPage: Int,
        to nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        let node = OutlineNode(title: title, startPage: startPage, endPage: endPage)
        return try inserting(node, parentID: nil, at: nodes.count, into: nodes)
    }

    static func addSibling(
        after nodeID: UUID,
        title: String,
        startPage: Int,
        endPage: Int,
        in nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        guard let location = location(of: nodeID, in: nodes) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        let node = OutlineNode(title: title, startPage: startPage, endPage: endPage)
        return try inserting(
            node,
            parentID: location.parentID,
            at: location.index + 1,
            into: nodes
        )
    }

    static func addChild(
        to parentID: UUID,
        title: String,
        startPage: Int,
        endPage: Int,
        in nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        guard let parent = findNode(id: parentID, in: nodes) else {
            throw FreeNoteError.outlineParentNotFound(parentID)
        }
        let node = OutlineNode(title: title, startPage: startPage, endPage: endPage)
        return try inserting(node, parentID: parentID, at: parent.children.count, into: nodes)
    }

    static func rename(nodeID: UUID, title: String, in nodes: [OutlineNode]) throws -> [OutlineNode] {
        try replacing(nodeID: nodeID, in: nodes) { node in
            node.title = title
        }
    }

    static func setPageRange(
        nodeID: UUID,
        startPage: Int,
        endPage: Int,
        pageCount: Int,
        in nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        guard startPage >= 1, endPage >= startPage, endPage <= pageCount else {
            throw FreeNoteError.invalidOutlineRange(
                nodeID: nodeID,
                startPage: startPage,
                endPage: endPage
            )
        }
        return try replacing(nodeID: nodeID, in: nodes) { node in
            node.startPage = startPage
            node.endPage = endPage
        }
    }

    static func deleteSubtree(nodeID: UUID, from nodes: [OutlineNode]) throws -> [OutlineNode] {
        guard findNode(id: nodeID, in: nodes) != nil else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        return try removing(nodeID: nodeID, from: nodes, depth: 1)
    }

    static func indent(nodeID: UUID, in nodes: [OutlineNode]) throws -> [OutlineNode] {
        guard let location = location(of: nodeID, in: nodes) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        guard location.index > 0 else {
            return nodes
        }
        let siblings = location.parentID.flatMap { findNode(id: $0, in: nodes)?.children } ?? nodes
        let previousSibling = siblings[location.index - 1]
        return try moveSubtree(
            nodeID: nodeID,
            toParentID: previousSibling.id,
            at: previousSibling.children.count,
            in: nodes
        )
    }

    static func outdent(nodeID: UUID, in nodes: [OutlineNode]) throws -> [OutlineNode] {
        guard let location = location(of: nodeID, in: nodes),
              let directParentID = location.parentID,
              let parentLocation = location(of: directParentID, in: nodes) else {
            return nodes
        }
        return try moveSubtree(
            nodeID: nodeID,
            toParentID: parentLocation.parentID,
            at: parentLocation.index + 1,
            in: nodes
        )
    }

    static func moveUp(nodeID: UUID, in nodes: [OutlineNode]) throws -> [OutlineNode] {
        guard let location = location(of: nodeID, in: nodes), location.index > 0 else {
            return nodes
        }
        return try moveSubtree(
            nodeID: nodeID,
            toParentID: location.parentID,
            at: location.index - 1,
            in: nodes
        )
    }

    static func moveDown(nodeID: UUID, in nodes: [OutlineNode]) throws -> [OutlineNode] {
        guard let location = location(of: nodeID, in: nodes) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        let siblings = location.parentID.flatMap { findNode(id: $0, in: nodes)?.children } ?? nodes
        guard location.index < siblings.count - 1 else {
            return nodes
        }
        return try moveSubtree(
            nodeID: nodeID,
            toParentID: location.parentID,
            at: location.index + 1,
            in: nodes
        )
    }

    static func moveSubtree(
        nodeID: UUID,
        toParentID: UUID?,
        at destinationIndex: Int,
        in nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        guard let movingNode = findNode(id: nodeID, in: nodes) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        if let toParentID, subtreeIDs(of: nodeID, in: nodes).contains(toParentID) {
            throw FreeNoteError.invalidOutlineMove
        }
        if let toParentID, findNode(id: toParentID, in: nodes) == nil {
            throw FreeNoteError.outlineParentNotFound(toParentID)
        }
        let remaining = try removing(nodeID: nodeID, from: nodes, depth: 1)
        let result = try inserting(
            movingNode,
            parentID: toParentID,
            at: destinationIndex,
            into: remaining
        )
        try validate(result)
        return result
    }

    /// Remaps outline page ranges after page deletion. Nodes whose entire range disappears
    /// are removed, while their surviving children are promoted to the parent level.
    static func remapPageRanges(
        _ nodes: [OutlineNode],
        oldPageIDs: [UUID],
        newPageIDs: [UUID]
    ) throws -> [OutlineNode] {
        var oldIndexByID: [UUID: Int] = [:]
        for (offset, id) in oldPageIDs.enumerated() {
            if oldIndexByID[id] != nil {
                throw FreeNoteError.duplicatePageID(id)
            }
            oldIndexByID[id] = offset + 1
        }

        var newIndexByOldIndex: [Int: Int] = [:]
        for (offset, id) in newPageIDs.enumerated() {
            guard let oldIndex = oldIndexByID[id] else {
                throw FreeNoteError.invalidState("页面迁移时出现未知页面标识。")
            }
            newIndexByOldIndex[oldIndex] = offset + 1
        }

        func remap(_ source: [OutlineNode], depth: Int) throws -> [OutlineNode] {
            if depth > maximumDepth {
                throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
            }
            var result: [OutlineNode] = []
            result.reserveCapacity(source.count)
            for var node in source {
                let survivingChildren = try remap(node.children, depth: depth + 1)
                var mappedPages: [Int] = []
                if node.startPage <= node.endPage {
                    for oldPage in node.startPage...node.endPage {
                        if let newPage = newIndexByOldIndex[oldPage] {
                            mappedPages.append(newPage)
                        }
                    }
                }
                if let first = mappedPages.min(), let last = mappedPages.max() {
                    node.startPage = first
                    node.endPage = last
                    node.children = survivingChildren
                    result.append(node)
                } else {
                    result.append(contentsOf: survivingChildren)
                }
            }
            return result
        }

        let result = try remap(nodes, depth: 1)
        try validate(result, pageCount: newPageIDs.count)
        return result
    }

    private static func location(
        of id: UUID,
        in nodes: [OutlineNode]
    ) -> (parentID: UUID?, index: Int, path: [OutlineNode])? {
        var stack: [(node: OutlineNode, parentID: UUID?, index: Int, path: [OutlineNode])] =
            nodes.enumerated().reversed().map { ($0.element, nil, $0.offset, [$0.element]) }

        while let entry = stack.popLast() {
            if entry.path.count > maximumDepth {
                return nil
            }
            if entry.node.id == id {
                return (entry.parentID, entry.index, entry.path)
            }
            if !entry.node.children.isEmpty {
                let childEntries = entry.node.children.enumerated().reversed().map {
                    (child: $0.element,
                     parentID: entry.node.id,
                     index: $0.offset,
                     path: entry.path + [$0.element])
                }
                stack.append(contentsOf: childEntries)
            }
        }
        return nil
    }

    private static func inserting(
        _ node: OutlineNode,
        parentID: UUID?,
        at requestedIndex: Int,
        into nodes: [OutlineNode]
    ) throws -> [OutlineNode] {
        guard let result = try insert(
            node,
            parentID: parentID,
            at: requestedIndex,
            into: nodes,
            depth: 1
        ) else {
            throw FreeNoteError.outlineParentNotFound(parentID ?? node.id)
        }
        try validate(result)
        return result
    }

    private static func insert(
        _ node: OutlineNode,
        parentID: UUID?,
        at requestedIndex: Int,
        into nodes: [OutlineNode],
        depth: Int
    ) throws -> [OutlineNode]? {
        if depth > maximumDepth {
            throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
        }
        if parentID == nil {
            var result = nodes
            let index = min(max(requestedIndex, 0), result.count)
            result.insert(node, at: index)
            return result
        }
        for index in nodes.indices {
            if nodes[index].id == parentID {
                var result = nodes
                let childIndex = min(max(requestedIndex, 0), result[index].children.count)
                result[index].children.insert(node, at: childIndex)
                return result
            }
        }
        for index in nodes.indices {
            if let updatedChildren = try insert(
                node,
                parentID: parentID,
                at: requestedIndex,
                into: nodes[index].children,
                depth: depth + 1
            ) {
                var result = nodes
                result[index].children = updatedChildren
                return result
            }
        }
        return nil
    }

    private static func removing(
        nodeID: UUID,
        from nodes: [OutlineNode],
        depth: Int
    ) throws -> [OutlineNode] {
        if depth > maximumDepth {
            throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
        }
        guard let result = try removeIfPresent(
            nodeID: nodeID,
            from: nodes,
            depth: depth
        ) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        return result
    }

    private static func removeIfPresent(
        nodeID: UUID,
        from nodes: [OutlineNode],
        depth: Int
    ) throws -> [OutlineNode]? {
        if depth > maximumDepth {
            throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
        }
        if nodes.contains(where: { $0.id == nodeID }) {
            return nodes.filter { $0.id != nodeID }
        }
        var result = nodes
        for index in result.indices {
            guard let updatedChildren = try removeIfPresent(
                nodeID: nodeID,
                from: result[index].children,
                depth: depth + 1
            ) else {
                continue
            }
            result[index].children = updatedChildren
            return result
        }
        return nil
    }

    private static func replacing(
        nodeID: UUID,
        in nodes: [OutlineNode],
        transform: (inout OutlineNode) -> Void
    ) throws -> [OutlineNode] {
        guard let path = path(to: nodeID, in: nodes) else {
            throw FreeNoteError.outlineNodeNotFound(nodeID)
        }
        guard path.count <= maximumDepth else {
            throw FreeNoteError.invalidState("大纲层级超过安全上限 \(maximumDepth)。")
        }

        func replace(_ source: [OutlineNode], pathIndex: Int) -> [OutlineNode] {
            var result = source
            let targetID = path[pathIndex].id
            guard let index = result.firstIndex(where: { $0.id == targetID }) else {
                return result
            }
            if pathIndex == path.count - 1 {
                transform(&result[index])
            } else {
                result[index].children = replace(result[index].children, pathIndex: pathIndex + 1)
            }
            return result
        }

        return replace(nodes, pathIndex: 0)
    }
}
