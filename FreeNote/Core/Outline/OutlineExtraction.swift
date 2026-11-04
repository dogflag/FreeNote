import Foundation
import PDFKit

struct DocumentOutlineInfo: Sendable {
    let pageCount: Int
    let outline: [OutlineNode]
    let usedEmbeddedOutline: Bool
    let warning: String?
}

enum DocumentOutlineExtractor {
    private static let maximumPDFHeuristicPages = 500

    static func inspect(url: URL, kind: DocumentKind) -> DocumentOutlineInfo {
        switch kind {
        case .pdf:
            return inspectPDF(url: url)
        case .epub:
            let result = EPUBOutlineExtractor.inspect(url: url)
            return withFallback(result)
        case .office:
            let result = PPTXOutlineExtractor.inspect(url: url)
            return withFallback(result)
        case .image, .audio, .text, .other:
            return DocumentOutlineInfo(
                pageCount: 1,
                outline: fallbackOutline(pageCount: 1),
                usedEmbeddedOutline: false,
                warning: nil
            )
        }
    }

    static func fallbackOutline(pageCount: Int, titles: [String]? = nil) -> [OutlineNode] {
        guard pageCount > 0 else {
            return []
        }
        return (1...pageCount).map { page in
            let candidate = titles.flatMap { page <= $0.count ? $0[page - 1] : nil }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if let candidate, !candidate.isEmpty {
                title = candidate
            } else {
                title = "第 \(page) 页"
            }
            return OutlineNode(title: title, startPage: page, endPage: page)
        }
    }

    static func looksLikeChapterHeading(_ text: String) -> Bool {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count >= 2, compact.count <= 120,
              let expression = chapterHeadingExpression,
              let match = expression.firstMatch(
                in: compact,
                range: NSRange(compact.startIndex..., in: compact)
              ) else {
            return false
        }
        return match.range.location == 0
    }

    static func headingOutline(
        from candidates: [(page: Int, title: String)],
        pageCount: Int
    ) -> [OutlineNode] {
        guard pageCount > 0 else {
            return []
        }
        var uniqueByPage: [Int: String] = [:]
        for candidate in candidates where candidate.page >= 1 && candidate.page <= pageCount {
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, uniqueByPage[candidate.page] == nil {
                uniqueByPage[candidate.page] = title
            }
        }
        let pages = uniqueByPage.keys.sorted()
        return pages.enumerated().map { offset, page in
            let endPage = offset + 1 < pages.count ? pages[offset + 1] - 1 : pageCount
            return OutlineNode(
                title: uniqueByPage[page] ?? "第 \(page) 页",
                startPage: page,
                endPage: max(page, endPage)
            )
        }
    }

    private static func withFallback(_ result: DocumentOutlineInfo) -> DocumentOutlineInfo {
        guard result.pageCount > 0 else {
            return result
        }
        if result.outline.isEmpty {
            return DocumentOutlineInfo(
                pageCount: result.pageCount,
                outline: fallbackOutline(pageCount: result.pageCount),
                usedEmbeddedOutline: false,
                warning: result.warning
            )
        }
        return result
    }

    private static func inspectPDF(url: URL) -> DocumentOutlineInfo {
        guard let document = PDFDocument(url: url) else {
            return DocumentOutlineInfo(
                pageCount: 0,
                outline: [],
                usedEmbeddedOutline: false,
                warning: "无法读取 PDF 文档。"
            )
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            return DocumentOutlineInfo(
                pageCount: 0,
                outline: [],
                usedEmbeddedOutline: false,
                warning: "PDF 没有可读取的页面。"
            )
        }

        if let root = document.outlineRoot {
            let rawNodes = makeRawPDFNodes(from: root, document: document, depth: 1)
            let outline = makePDFOutline(nodes: rawNodes, lowerBound: 1, upperBound: pageCount, depth: 1)
            if !outline.isEmpty,
               (try? OutlineEditor.validate(outline, pageCount: pageCount)) != nil {
                return DocumentOutlineInfo(
                    pageCount: pageCount,
                    outline: outline,
                    usedEmbeddedOutline: true,
                    warning: nil
                )
            }
        }

        let candidates = pdfHeadingCandidates(document: document, pageCount: pageCount)
        let outline = headingOutline(from: candidates, pageCount: pageCount)
        if !outline.isEmpty {
            return DocumentOutlineInfo(
                pageCount: pageCount,
                outline: outline,
                usedEmbeddedOutline: false,
                warning: nil
            )
        }
        return DocumentOutlineInfo(
            pageCount: pageCount,
            outline: fallbackOutline(pageCount: pageCount),
            usedEmbeddedOutline: false,
            warning: nil
        )
    }

    private static func pdfHeadingCandidates(
        document: PDFDocument,
        pageCount: Int
    ) -> [(page: Int, title: String)] {
        guard pageCount <= maximumPDFHeuristicPages else {
            return []
        }
        var candidates: [(page: Int, title: String)] = []
        for pageIndex in 0..<pageCount {
            guard let text = document.page(at: pageIndex)?.string else {
                continue
            }
            guard let firstLine = text
                .split(whereSeparator: { $0.isNewline })
                .map(String.init)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
                continue
            }
            if looksLikeChapterHeading(firstLine) {
                candidates.append((pageIndex + 1, firstLine))
            }
        }
        return candidates
    }

    private static func makeRawPDFNodes(
        from outline: PDFOutline,
        document: PDFDocument,
        depth: Int
    ) -> [PDFRawNode] {
        guard depth <= OutlineEditor.maximumDepth else {
            return []
        }
        var nodes: [PDFRawNode] = []
        let childCount = outline.numberOfChildren
        guard childCount > 0 else {
            return []
        }
        for index in 0..<childCount {
            guard let child = outline.child(at: index) else {
                continue
            }
            let pageNumber: Int?
            if let page = child.destination?.page {
                let zeroBasedIndex = document.index(for: page)
                pageNumber = zeroBasedIndex >= 0 ? zeroBasedIndex + 1 : nil
            } else {
                pageNumber = nil
            }
            let trimmedLabel = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedLabel?.isEmpty == false ? trimmedLabel ?? "未命名章节" : "未命名章节"
            let node = PDFRawNode(
                title: title,
                page: pageNumber,
                children: makeRawPDFNodes(from: child, document: document, depth: depth + 1)
            )
            if node.effectiveStartPage != nil {
                nodes.append(node)
            }
        }
        return nodes
    }

    private static func makePDFOutline(
        nodes: [PDFRawNode],
        lowerBound: Int,
        upperBound: Int,
        depth: Int
    ) -> [OutlineNode] {
        guard depth <= OutlineEditor.maximumDepth, lowerBound <= upperBound else {
            return []
        }
        var result: [OutlineNode] = []
        for (index, rawNode) in nodes.enumerated() {
            guard let rawStart = rawNode.effectiveStartPage else {
                continue
            }
            let start = min(max(rawStart, lowerBound), upperBound)
            let nextStart = nodes[(index + 1)...]
                .compactMap(\.effectiveStartPage)
                .first
            let end = nextStart.map { min(upperBound, max(start, $0 - 1)) } ?? upperBound
            let children = makePDFOutline(
                nodes: rawNode.children,
                lowerBound: start,
                upperBound: end,
                depth: depth + 1
            )
            result.append(
                OutlineNode(
                    title: rawNode.title,
                    startPage: start,
                    endPage: end,
                    children: children
                )
            )
        }
        return result
    }

    private static var chapterHeadingExpression: NSRegularExpression? {
        let pattern = "^(?:(?:第\\s*[0-9一二三四五六七八九十百千零〇两]+\\s*[章节篇卷部回])|(?:chapter|part|book)\\s+(?:[0-9]+|[ivxlcdm]+)\\b|(?:prologue|epilogue)\\b|(?:序言|序|前言|引言|目录|后记|附录)(?:\\s|[:：]|$))"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

private final class PDFRawNode {
    let title: String
    let page: Int?
    let children: [PDFRawNode]
    let effectiveStartPage: Int?

    init(title: String, page: Int?, children: [PDFRawNode]) {
        self.title = title
        self.page = page
        self.children = children
        self.effectiveStartPage = page ?? children.compactMap(\.effectiveStartPage).min()
    }
}
