import XCTest
@testable import FreeNote

final class DocumentOutlineExtractorTests: XCTestCase {
    func testFallbackCreatesOneTopLevelNodePerPageWithoutChildren() throws {
        let outline = DocumentOutlineExtractor.fallbackOutline(pageCount: 4)
        XCTAssertEqual(outline.count, 4)
        XCTAssertEqual(outline.map(\.startPage), [1, 2, 3, 4])
        XCTAssertEqual(outline.map(\.endPage), [1, 2, 3, 4])
        XCTAssertTrue(outline.allSatisfy { $0.children.isEmpty })
        XCTAssertNoThrow(try OutlineEditor.validate(outline, pageCount: 4))
    }

    func testHeadingOutlineUsesContinuousRanges() throws {
        let outline = DocumentOutlineExtractor.headingOutline(
            from: [(page: 1, title: "第一章"), (page: 4, title: "第二章")],
            pageCount: 6
        )
        XCTAssertEqual(outline.count, 2)
        XCTAssertEqual(outline[0].startPage, 1)
        XCTAssertEqual(outline[0].endPage, 3)
        XCTAssertEqual(outline[1].startPage, 4)
        XCTAssertEqual(outline[1].endPage, 6)
    }

    func testChapterHeadingHeuristic() {
        XCTAssertTrue(DocumentOutlineExtractor.looksLikeChapterHeading("第一章 起点"))
        XCTAssertTrue(DocumentOutlineExtractor.looksLikeChapterHeading("Chapter 2"))
        XCTAssertTrue(DocumentOutlineExtractor.looksLikeChapterHeading("前言"))
        XCTAssertFalse(DocumentOutlineExtractor.looksLikeChapterHeading("这是一段普通正文"))
    }

    func testZipPathTraversalIsRejected() {
        XCTAssertFalse(ZIPArchiveReader.isSafeArchivePath("../escape.xml"))
        XCTAssertFalse(ZIPArchiveReader.isSafeArchivePath("OEBPS/../../escape.xml"))
        XCTAssertFalse(ZIPArchiveReader.isSafeArchivePath("/absolute/path.xml"))
        XCTAssertTrue(ZIPArchiveReader.isSafeArchivePath("OEBPS/content.opf"))
    }
}
