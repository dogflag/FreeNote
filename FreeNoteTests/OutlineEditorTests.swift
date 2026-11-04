import XCTest
@testable import FreeNote

final class OutlineEditorTests: XCTestCase {
    func testValidationAcceptsSinglePageAndRejectsInvalidRanges() throws {
        let valid = [
            OutlineNode(title: "一", startPage: 1, endPage: 1),
            OutlineNode(title: "二", startPage: 2, endPage: 3)
        ]
        XCTAssertNoThrow(try OutlineEditor.validate(valid, pageCount: 3))

        let invalid = [OutlineNode(title: "错误", startPage: 0, endPage: 1)]
        XCTAssertThrowsError(try OutlineEditor.validate(invalid, pageCount: 3))

        let outOfBounds = [OutlineNode(title: "越界", startPage: 2, endPage: 4)]
        XCTAssertThrowsError(try OutlineEditor.validate(outOfBounds, pageCount: 3))
    }

    func testFindMoveAndDeleteRecursiveNodes() throws {
        let deepID = UUID()
        var tree = [
            OutlineNode(
                title: "根",
                startPage: 1,
                endPage: 10,
                children: [
                    OutlineNode(title: "子", startPage: 1, endPage: 5),
                    OutlineNode(title: "目标", startPage: 6, endPage: 10)
                ]
            )
        ]
        let childID = tree[0].children[1].id
        XCTAssertEqual(OutlineEditor.parentID(of: childID, in: tree), tree[0].id)
        XCTAssertEqual(OutlineEditor.findNode(id: childID, in: tree)?.title, "目标")

        tree = try OutlineEditor.indent(nodeID: childID, in: tree)
        let firstChildID = tree[0].children[0].id
        XCTAssertEqual(OutlineEditor.parentID(of: childID, in: tree), firstChildID)
        XCTAssertEqual(OutlineEditor.path(to: childID, in: tree)?.count, 3)

        tree = try OutlineEditor.outdent(nodeID: childID, in: tree)
        XCTAssertEqual(OutlineEditor.parentID(of: childID, in: tree), tree[0].id)

        let nested = OutlineNode(
            id: deepID,
            title: "删除我",
            startPage: 2,
            endPage: 3,
            children: [OutlineNode(title: "孙", startPage: 2, endPage: 3)]
        )
        tree[0].children.append(nested)
        tree = try OutlineEditor.deleteSubtree(nodeID: deepID, from: tree)
        XCTAssertNil(OutlineEditor.findNode(id: deepID, in: tree))
    }

    func testRemovalAndMoveSearchEverySiblingBranch() throws {
        let target = OutlineNode(title: "目标", startPage: 2, endPage: 2)
        let secondBranch = OutlineNode(
            title: "第二分支",
            startPage: 2,
            endPage: 3,
            children: [target]
        )
        let firstBranch = OutlineNode(
            title: "第一分支",
            startPage: 1,
            endPage: 1,
            children: [OutlineNode(title: "无关", startPage: 1, endPage: 1)]
        )
        let root = OutlineNode(
            title: "根",
            startPage: 1,
            endPage: 3,
            children: [firstBranch, secondBranch]
        )

        let afterDelete = try OutlineEditor.deleteSubtree(nodeID: target.id, from: [root])
        XCTAssertEqual(afterDelete[0].children.count, 2)
        XCTAssertTrue(afterDelete[0].children[1].children.isEmpty)

        let secondTarget = OutlineNode(title: "移动目标", startPage: 2, endPage: 2)
        let secondBranchWithTarget = OutlineNode(
            title: "第二分支",
            startPage: 2,
            endPage: 3,
            children: [secondTarget]
        )
        let moveTree = [
            OutlineNode(
                title: "根",
                startPage: 1,
                endPage: 3,
                children: [firstBranch, secondBranchWithTarget]
            )
        ]
        let moved = try OutlineEditor.moveSubtree(
            nodeID: secondTarget.id,
            toParentID: firstBranch.id,
            at: 1,
            in: moveTree
        )
        XCTAssertEqual(
            OutlineEditor.parentID(of: secondTarget.id, in: moved),
            firstBranch.id
        )
    }

    func testMoveIntoOwnDescendantIsRejected() throws {
        let child = OutlineNode(title: "子", startPage: 1, endPage: 2)
        let root = OutlineNode(title: "根", startPage: 1, endPage: 2, children: [child])
        XCTAssertThrowsError(
            try OutlineEditor.moveSubtree(
                nodeID: root.id,
                toParentID: child.id,
                at: 0,
                in: [root]
            )
        )
    }

    func testRemapPageRangesAfterDeletion() throws {
        let oldPages = [UUID(), UUID(), UUID()]
        let newPages = [oldPages[0], oldPages[2]]
        let tree = [
            OutlineNode(
                title: "章节",
                startPage: 1,
                endPage: 3,
                children: [
                    OutlineNode(title: "一节", startPage: 1, endPage: 1),
                    OutlineNode(title: "二节", startPage: 2, endPage: 3)
                ]
            )
        ]

        let remapped = try OutlineEditor.remapPageRanges(
            tree,
            oldPageIDs: oldPages,
            newPageIDs: newPages
        )

        XCTAssertEqual(remapped.count, 1)
        XCTAssertEqual(remapped[0].startPage, 1)
        XCTAssertEqual(remapped[0].endPage, 2)
        XCTAssertEqual(remapped[0].children.count, 2)
        XCTAssertEqual(remapped[0].children[1].startPage, 2)
        XCTAssertEqual(remapped[0].children[1].endPage, 2)
        XCTAssertNoThrow(try OutlineEditor.validate(remapped, pageCount: 2))
    }

    func testDefensiveDepthLimit() {
        var node = OutlineNode(title: "叶", startPage: 1, endPage: 1)
        for _ in 0..<OutlineEditor.maximumDepth {
            node = OutlineNode(title: "层", startPage: 1, endPage: 1, children: [node])
        }
        XCTAssertThrowsError(try OutlineEditor.validate([node], pageCount: 1))
    }
}
