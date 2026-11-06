import Foundation
import PDFKit
import UIKit

enum OfficePreviewRenderer {
    static func pageCount(for url: URL, kind: DocumentKind) throws -> Int {
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                throw FreeNoteError.documentHasNoReadablePages(url.lastPathComponent)
            }
            return document.pageCount
        case .epub:
            let document = try EPUBPreviewDocument.load(url: url)
            guard !document.spinePaths.isEmpty else {
                throw FreeNoteError.documentHasNoReadablePages(url.lastPathComponent)
            }
            return document.spinePaths.count
        case .office:
            if url.pathExtension.lowercased() == "pptx" {
                let paths = try PowerPointPreview.slidePaths(url: url)
                guard !paths.isEmpty else {
                    throw FreeNoteError.documentHasNoReadablePages(url.lastPathComponent)
                }
                return paths.count
            }
            return 1
        case .image, .audio, .text, .other:
            return 1
        }
    }

    static func previewHTML(for url: URL, kind: DocumentKind) throws -> String? {
        try previewHTML(for: url, kind: kind, pageIndex: nil)
    }

    static func previewHTML(
        for url: URL,
        kind: DocumentKind,
        pageIndex: Int?
    ) throws -> String? {
        switch kind {
        case .pdf:
            return nil
        case .epub:
            return try EPUBPreviewDocument.load(url: url).renderHTML(pageIndex: pageIndex)
        case .office:
            switch url.pathExtension.lowercased() {
            case "docx":
                return try DOCXPreview.render(url: url, pageIndex: pageIndex)
            case "pptx":
                return try PowerPointPreview.render(url: url, pageIndex: pageIndex)
            case "xlsx":
                return try ExcelPreview.render(url: url, pageIndex: pageIndex)
            case "doc", "ppt", "xls":
                return try LegacyOfficePreview.render(url: url, pageIndex: pageIndex)
            default:
                throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
            }
        case .image, .audio, .text, .other:
            return nil
        }
    }

    static func validatePreviewPageIndex(
        _ pageIndex: Int?,
        pageCount: Int,
        fileName: String
    ) throws {
        guard let pageIndex else {
            return
        }
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw FreeNoteError.invalidState(
                "预览页码 \(pageIndex) 超出范围 0..<\(pageCount)：\(fileName)"
            )
        }
    }

    static func htmlDocument(title: String, body: String) -> String {
        let escapedTitle = escapeHTML(title)
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle)</title>
          <style>
            :root { color-scheme: light dark; }
            body { margin: 0; padding: 24px; font: 17px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; color: #26322f; background: #fcfaf5; }
            h1, h2, h3 { color: #34483d; line-height: 1.3; }
            h1 { font-size: 28px; }
            h2 { font-size: 22px; }
            h3 { font-size: 19px; }
            p { margin: 0 0 14px; white-space: pre-wrap; }
            pre { white-space: pre-wrap; word-break: break-word; font: inherit; }
            section { page-break-after: always; border-bottom: 1px solid #e3ded3; padding-bottom: 24px; margin-bottom: 24px; }
            section:last-child { page-break-after: auto; border-bottom: 0; }
            table { border-collapse: collapse; width: 100%; font-size: 14px; }
            td, th { border: 1px solid #d8d2c7; padding: 7px 9px; text-align: left; vertical-align: top; }
            tr:nth-child(even) { background: rgba(79, 103, 89, 0.06); }
            .empty { color: #7a817d; font-style: italic; }
            @media (prefers-color-scheme: dark) {
              body { color: #ece8df; background: #202522; }
              h1, h2, h3 { color: #dce8df; }
              td, th { border-color: #48514c; }
              section { border-color: #48514c; }
            }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    fileprivate static func decodeHTMLText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

private enum DOCXPreview {
    struct Block {
        let text: String
        let headingLevel: Int?
    }

    static func render(url: URL, pageIndex: Int?) throws -> String {
        try OfficePreviewRenderer.validatePreviewPageIndex(
            pageIndex,
            pageCount: 1,
            fileName: url.lastPathComponent
        )
        guard let reader = try? ZIPArchiveReader(url: url),
              let data = reader.read(path: "word/document.xml", maximumBytes: 16 * 1024 * 1024),
              let blocks = DOCXParser.parse(data: data),
              !blocks.isEmpty else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }

        let blockHTML = blocks.map { block -> String in
            let text = OfficePreviewRenderer.escapeHTML(block.text)
            if let level = block.headingLevel {
                return "<h\(min(max(level, 1), 3))>\(text)</h\(min(max(level, 1), 3))>"
            }
            return "<p>\(text)</p>"
        }.joined(separator: "\n")
        let body = "<section data-page-index=\"0\">\n\(blockHTML)\n</section>"
        return OfficePreviewRenderer.htmlDocument(title: url.deletingPathExtension().lastPathComponent, body: body)
    }

    private final class DOCXParser: NSObject, XMLParserDelegate {
        private var blocks: [Block] = []
        private var inParagraph = false
        private var collectingText = false
        private var paragraphText = ""
        private var paragraphStyle: String?

        static func parse(data: Data) -> [Block]? {
            let delegate = DOCXParser()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse() else {
                return delegate.blocks.isEmpty ? nil : delegate.blocks
            }
            return delegate.blocks.isEmpty ? nil : delegate.blocks
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch previewLocalName(elementName) {
            case "p":
                inParagraph = true
                paragraphText = ""
                paragraphStyle = nil
            case "pstyle":
                paragraphStyle = previewAttribute("val", in: attributeDict)
            case "t":
                collectingText = inParagraph
            case "tab":
                if inParagraph {
                    paragraphText += "\t"
                }
            case "br":
                if inParagraph {
                    paragraphText += "\n"
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inParagraph, collectingText {
                paragraphText += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch previewLocalName(elementName) {
            case "t":
                collectingText = false
            case "p":
                let text = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    blocks.append(Block(text: text, headingLevel: headingLevel(for: paragraphStyle)))
                }
                inParagraph = false
                collectingText = false
                paragraphText = ""
                paragraphStyle = nil
            default:
                break
            }
        }

        private func headingLevel(for style: String?) -> Int? {
            guard let style else {
                return nil
            }
            let normalized = style.lowercased()
            if normalized.contains("title") {
                return 1
            }
            if normalized.contains("heading") {
                let digits = normalized.compactMap { $0.wholeNumberValue }.first
                return min(max(digits ?? 1, 1), 3)
            }
            if ["1", "2", "3"].contains(normalized) {
                return Int(normalized)
            }
            return nil
        }
    }
}

private enum PowerPointPreview {
    static func slidePaths(url: URL) throws -> [String] {
        guard let reader = try? ZIPArchiveReader(url: url) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        let expression = try? NSRegularExpression(
            pattern: "^ppt/slides/slide([0-9]+)\\.xml$",
            options: [.caseInsensitive]
        )
        guard let expression else {
            return []
        }
        var slides: [(number: Int, path: String)] = []
        for path in reader.paths {
            let range = NSRange(path.startIndex..., in: path)
            guard let match = expression.firstMatch(in: path, range: range),
                  let numberRange = Range(match.range(at: 1), in: path),
                  let number = Int(path[numberRange]) else {
                continue
            }
            slides.append((number, path))
        }
        return slides.sorted { $0.number < $1.number }.map(\.path)
    }

    static func render(url: URL, pageIndex: Int?) throws -> String {
        guard let reader = try? ZIPArchiveReader(url: url) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        let paths = try slidePaths(url: url)
        guard !paths.isEmpty else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        try OfficePreviewRenderer.validatePreviewPageIndex(
            pageIndex,
            pageCount: paths.count,
            fileName: url.lastPathComponent
        )

        let indexes = pageIndex.map { [$0] } ?? Array(paths.indices)
        var sections: [String] = []
        for index in indexes {
            let path = paths[index]
            let texts = reader.read(path: path, maximumBytes: 8 * 1024 * 1024)
                .flatMap { XMLTextRuns.parse(data: $0, elementLocalName: "t") } ?? []
            let heading = texts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if let heading, !heading.isEmpty {
                title = heading
            } else {
                title = "第 \(index + 1) 页"
            }
            let remaining = texts.dropFirst().joined(separator: "\n")
            let bodyText = remaining.isEmpty ? "（无文本内容）" : remaining
            sections.append("""
            <section data-page-index="\(index)">
              <h2>\(OfficePreviewRenderer.escapeHTML(title))</h2>
              <p>\(OfficePreviewRenderer.escapeHTML(bodyText))</p>
            </section>
            """)
        }
        return OfficePreviewRenderer.htmlDocument(
            title: url.deletingPathExtension().lastPathComponent,
            body: sections.joined(separator: "\n")
        )
    }
}

private enum ExcelPreview {
    static func render(url: URL, pageIndex: Int?) throws -> String {
        try OfficePreviewRenderer.validatePreviewPageIndex(
            pageIndex,
            pageCount: 1,
            fileName: url.lastPathComponent
        )
        guard let reader = try? ZIPArchiveReader(url: url) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        let sharedStrings: [String]
        if let data = reader.read(path: "xl/sharedStrings.xml", maximumBytes: 8 * 1024 * 1024) {
            sharedStrings = SharedStringsParser.parse(data: data)
        } else {
            sharedStrings = []
        }

        let worksheetPaths = reader.paths.compactMap { path -> (number: Int, path: String)? in
            let pattern = "^xl/worksheets/sheet([0-9]+)\\.xml$"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            let range = NSRange(path.startIndex..., in: path)
            guard let match = expression.firstMatch(in: path, range: range),
                  let numberRange = Range(match.range(at: 1), in: path),
                  let number = Int(path[numberRange]) else {
                return nil
            }
            return (number, path)
        }.sorted { $0.number < $1.number }

        guard let firstSheet = worksheetPaths.first,
              let data = reader.read(path: firstSheet.path, maximumBytes: 16 * 1024 * 1024),
              let rows = WorksheetParser.parse(data: data, sharedStrings: sharedStrings),
              !rows.isEmpty else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }

        let maxColumn = rows.flatMap { $0.value.keys }.max() ?? 1
        let body = rows.keys.sorted().map { rowIndex -> String in
            let cells = (1...maxColumn).map { columnIndex -> String in
                let value = rows[rowIndex]?[columnIndex] ?? ""
                return "<td>\(OfficePreviewRenderer.escapeHTML(value))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")

        let table = """
        <section data-page-index=\"0\">
        <table>
          <tbody>
        \(body)
          </tbody>
        </table>
        </section>
        """
        return OfficePreviewRenderer.htmlDocument(
            title: url.deletingPathExtension().lastPathComponent,
            body: table
        )
    }

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        private var strings: [String] = []
        private var current = ""
        private var inString = false
        private var collecting = false

        static func parse(data: Data) -> [String] {
            let delegate = SharedStringsParser()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            _ = parser.parse()
            return delegate.strings
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch previewLocalName(elementName) {
            case "si":
                inString = true
                current = ""
            case "t":
                collecting = inString
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting {
                current += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch previewLocalName(elementName) {
            case "t":
                collecting = false
            case "si":
                strings.append(current)
                inString = false
                collecting = false
                current = ""
            default:
                break
            }
        }
    }

    private final class WorksheetParser: NSObject, XMLParserDelegate {
        private var rows: [Int: [Int: String]] = [:]
        private var currentReference = ""
        private var currentType = ""
        private var currentValue = ""
        private var collecting = false
        private let sharedStrings: [String]

        private init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        static func parse(data: Data, sharedStrings: [String]) -> [Int: [Int: String]]? {
            let delegate = WorksheetParser(sharedStrings: sharedStrings)
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), !delegate.rows.isEmpty else {
                return nil
            }
            return delegate.rows
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch previewLocalName(elementName) {
            case "c":
                currentReference = previewAttribute("r", in: attributeDict) ?? ""
                currentType = previewAttribute("t", in: attributeDict) ?? ""
                currentValue = ""
                collecting = false
            case "v", "t":
                if !currentReference.isEmpty {
                    collecting = true
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting {
                currentValue += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch previewLocalName(elementName) {
            case "v", "t":
                collecting = false
            case "c":
                storeCurrentCell()
                currentReference = ""
                currentType = ""
                currentValue = ""
                collecting = false
            default:
                break
            }
        }

        private func storeCurrentCell() {
            guard !currentReference.isEmpty,
                  let coordinates = ExcelCoordinate(reference: currentReference) else {
                return
            }
            let value: String
            if currentType == "s", let index = Int(currentValue), sharedStrings.indices.contains(index) {
                value = sharedStrings[index]
            } else if currentType == "b" {
                value = currentValue == "1" ? "TRUE" : "FALSE"
            } else {
                value = currentValue
            }
            var row = rows[coordinates.row, default: [:]]
            row[coordinates.column] = value
            rows[coordinates.row] = row
        }
    }
}

private enum LegacyOfficePreview {
    static func render(url: URL, pageIndex: Int?) throws -> String {
        try OfficePreviewRenderer.validatePreviewPageIndex(
            pageIndex,
            pageCount: 1,
            fileName: url.lastPathComponent
        )
        do {
            let attributed = try NSAttributedString(
                url: url,
                options: [:],
                documentAttributes: nil
            )
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
            }
            let body = "<section data-page-index=\"0\"><pre>\(OfficePreviewRenderer.escapeHTML(text))</pre></section>"
            return OfficePreviewRenderer.htmlDocument(
                title: url.deletingPathExtension().lastPathComponent,
                body: body
            )
        } catch let error as FreeNoteError {
            throw error
        } catch {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
    }
}

private struct ExcelCoordinate {
    let row: Int
    let column: Int

    init?(reference: String) {
        let letters = reference.prefix { $0.isLetter }
        let digits = reference.dropFirst(letters.count)
        guard !letters.isEmpty, let row = Int(digits), row > 0 else {
            return nil
        }
        var column = 0
        for scalar in letters.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else {
                return nil
            }
            column = column * 26 + Int(scalar.value - 64)
        }
        guard column > 0 else {
            return nil
        }
        self.row = row
        self.column = column
    }
}

private final class XMLTextRuns: NSObject, XMLParserDelegate {
    private let targetLocalName: String
    private var runs: [String] = []
    private var current = ""
    private var collecting = false

    private init(targetLocalName: String) {
        self.targetLocalName = targetLocalName
    }

    static func parse(data: Data, elementLocalName: String) -> [String] {
        let delegate = XMLTextRuns(targetLocalName: elementLocalName)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return delegate.runs
        }
        return delegate.runs
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if previewLocalName(elementName) == targetLocalName {
            collecting = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting {
            current += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard previewLocalName(elementName) == targetLocalName else {
            return
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            runs.append(trimmed)
        }
        collecting = false
        current = ""
    }
}

private struct EPUBPreviewDocument {
    let url: URL
    let packagePath: String
    let spinePaths: [String]
    let navigationTitles: [String: String]

    static func load(url: URL) throws -> EPUBPreviewDocument {
        guard let reader = try? ZIPArchiveReader(url: url) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        guard let packagePath = locatePackagePath(reader: reader),
              let packageData = reader.read(path: packagePath, maximumBytes: 4 * 1024 * 1024),
              let package = EPUBPreviewPackageParser.parse(data: packageData) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }

        let spinePaths = package.spine.compactMap { id -> String? in
            guard let item = package.manifest[id],
                  let resolved = resolveArchivePath(item.href, relativeTo: packagePath) else {
                return nil
            }
            return actualArchivePath(resolved, in: reader)
        }
        guard !spinePaths.isEmpty else {
            throw FreeNoteError.documentHasNoReadablePages(url.lastPathComponent)
        }

        var navigationTitles: [String: String] = [:]
        if let navItem = package.manifest.values.first(where: {
            $0.properties.split(separator: " ").contains("nav")
        }), let resolved = resolveArchivePath(navItem.href, relativeTo: packagePath),
           let navPath = actualArchivePath(resolved, in: reader),
           let data = reader.read(path: navPath, maximumBytes: 8 * 1024 * 1024),
           let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            navigationTitles = EPUBNavigationTitles.parse(source: source, basePath: navPath)
        }

        return EPUBPreviewDocument(
            url: url,
            packagePath: packagePath,
            spinePaths: spinePaths,
            navigationTitles: navigationTitles
        )
    }

    func renderHTML(pageIndex: Int? = nil) throws -> String {
        guard let reader = try? ZIPArchiveReader(url: url) else {
            throw FreeNoteError.unsupportedPreview(url.lastPathComponent)
        }
        try OfficePreviewRenderer.validatePreviewPageIndex(
            pageIndex,
            pageCount: spinePaths.count,
            fileName: url.lastPathComponent
        )
        let indexes = pageIndex.map { [$0] } ?? Array(spinePaths.indices)
        var sections: [String] = []
        for index in indexes {
            let path = spinePaths[index]
            let data = reader.read(path: path, maximumBytes: 4 * 1024 * 1024)
            let source = data.flatMap {
                String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1)
            } ?? ""
            let heading = navigationTitles[path] ?? EPUBNavigationTitles.heading(from: source)
            let title: String
            if let heading, !heading.isEmpty {
                title = heading
            } else {
                title = "第 \(index + 1) 章"
            }
            let text = EPUBNavigationTitles.plainText(from: source)
            let paragraphs = text.split(whereSeparator: { $0.isNewline })
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "<p>\(OfficePreviewRenderer.escapeHTML($0))</p>" }
                .joined(separator: "\n")
            let body = paragraphs.isEmpty ? "<p class=\"empty\">（空章节）</p>" : paragraphs
            sections.append("""
            <section data-page-index="\(index)">
              <h2>\(OfficePreviewRenderer.escapeHTML(title))</h2>
              \(body)
            </section>
            """)
        }
        return OfficePreviewRenderer.htmlDocument(
            title: url.deletingPathExtension().lastPathComponent,
            body: sections.joined(separator: "\n")
        )
    }

    private static func locatePackagePath(reader: ZIPArchiveReader) -> String? {
        if let containerPath = reader.paths.first(where: {
            $0.caseInsensitiveCompare("META-INF/container.xml") == .orderedSame
        }), let data = reader.read(path: containerPath, maximumBytes: 2 * 1024 * 1024),
           let path = EPUBPreviewContainerParser.parse(data: data) {
            return actualArchivePath(path, in: reader)
        }
        return reader.paths.first { $0.lowercased().hasSuffix(".opf") }
    }
}

private struct EPUBPreviewManifestItem {
    let href: String
    let properties: String
}

private struct EPUBPreviewPackage {
    let manifest: [String: EPUBPreviewManifestItem]
    let spine: [String]
}

private final class EPUBPreviewContainerParser: NSObject, XMLParserDelegate {
    private var packagePath: String?

    static func parse(data: Data) -> String? {
        let delegate = EPUBPreviewContainerParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return delegate.packagePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if previewLocalName(elementName) == "rootfile" {
            packagePath = previewAttribute("full-path", in: attributeDict)
        }
    }
}

private final class EPUBPreviewPackageParser: NSObject, XMLParserDelegate {
    private var manifest: [String: EPUBPreviewManifestItem] = [:]
    private var spine: [String] = []

    static func parse(data: Data) -> EPUBPreviewPackage? {
        let delegate = EPUBPreviewPackageParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return EPUBPreviewPackage(manifest: delegate.manifest, spine: delegate.spine)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch previewLocalName(elementName) {
        case "item":
            guard let id = previewAttribute("id", in: attributeDict),
                  let href = previewAttribute("href", in: attributeDict) else {
                return
            }
            manifest[id] = EPUBPreviewManifestItem(
                href: href,
                properties: previewAttribute("properties", in: attributeDict) ?? ""
            )
        case "itemref":
            if let idref = previewAttribute("idref", in: attributeDict) {
                spine.append(idref)
            }
        default:
            break
        }
    }
}

private enum EPUBNavigationTitles {
    static func parse(source: String, basePath: String) -> [String: String] {
        let expression = try? NSRegularExpression(
            pattern: "<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard let expression else {
            return [:]
        }
        var result: [String: String] = [:]
        let range = NSRange(source.startIndex..., in: source)
        for match in expression.matches(in: source, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: source),
                  let titleRange = Range(match.range(at: 2), in: source),
                  let resolved = resolveArchivePath(String(source[hrefRange]), relativeTo: basePath) else {
                continue
            }
            let title = plainInlineText(String(source[titleRange]))
            if !title.isEmpty {
                result[resolved] = title
            }
        }
        return result
    }

    static func heading(from source: String) -> String? {
        let expression = try? NSRegularExpression(
            pattern: "<h[1-3]\\b[^>]*>(.*?)</h[1-3]\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard let expression else {
            return nil
        }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = expression.firstMatch(in: source, range: range),
              let titleRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        let title = plainInlineText(String(source[titleRange]))
        return title.isEmpty ? nil : title
    }

    static func plainText(from source: String) -> String {
        var value = source
        value = value.replacingOccurrences(
            of: "<script\\b[^>]*>.*?</script>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "<style\\b[^>]*>.*?</style>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "</(?:p|div|li|h[1-6]|blockquote|section)>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        value = OfficePreviewRenderer.decodeHTMLText(value)
        return value
            .split(whereSeparator: { $0.isNewline })
            .map { line in
                line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    private static func plainInlineText(_ source: String) -> String {
        let stripped = source.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return OfficePreviewRenderer.decodeHTMLText(stripped)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private func previewLocalName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
}

private func previewAttribute(_ key: String, in attributes: [String: String]) -> String? {
    if let direct = attributes[key] {
        return direct
    }
    return attributes.first {
        previewLocalName($0.key) == key.lowercased()
    }?.value
}

private func resolveArchivePath(_ link: String, relativeTo basePath: String) -> String? {
    let withoutFragment = link.split(separator: "#", maxSplits: 1).first.map(String.init) ?? link
    let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
    if decoded.isEmpty {
        return basePath
    }
    if decoded.hasPrefix("/") {
        return normalizeArchivePath(String(decoded.dropFirst()))
    }
    let baseDirectory = (basePath as NSString).deletingLastPathComponent
    let combined = baseDirectory.isEmpty ? decoded : baseDirectory + "/" + decoded
    return normalizeArchivePath(combined)
}

private func normalizeArchivePath(_ path: String) -> String? {
    var components: [String] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
        switch component {
        case ".":
            continue
        case "..":
            guard !components.isEmpty else {
                return nil
            }
            components.removeLast()
        default:
            guard !component.contains("\\"), !component.contains(":") else {
                return nil
            }
            components.append(String(component))
        }
    }
    return components.isEmpty ? nil : components.joined(separator: "/")
}

private func actualArchivePath(_ requested: String, in reader: ZIPArchiveReader) -> String? {
    if reader.contains(requested) {
        return requested
    }
    return reader.paths.first { $0.caseInsensitiveCompare(requested) == .orderedSame }
}
