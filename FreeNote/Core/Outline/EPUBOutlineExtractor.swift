import Foundation

enum EPUBOutlineExtractor {
    static func inspect(url: URL) -> DocumentOutlineInfo {
        guard let reader = try? ZIPArchiveReader(url: url) else {
            return failure("无法安全读取 EPUB 压缩包。")
        }

        let packagePath = locatePackagePath(reader: reader)
        guard let packagePath,
              let packageData = reader.read(path: packagePath, maximumBytes: 4 * 1024 * 1024),
              let package = EPUBPackageParser.parse(packageData) else {
            return failure("EPUB 的 package 文档无法读取。")
        }

        let spineItems = package.spine.compactMap { package.manifest[$0] }
        let spinePaths = spineItems.compactMap {
            resolveArchivePath($0.href, relativeTo: packagePath)
        }
        let pageCount = spinePaths.count
        guard pageCount > 0 else {
            return failure("EPUB 没有可用的阅读顺序。")
        }

        let lookup = EPUBSpineLookup(spinePaths: spinePaths)
        var tocItems: [EPUBTOCItem] = []
        var usedEmbedded = false
        var tocBasePath = packagePath

        if let navPath = locateNavigationDocument(package: package, packagePath: packagePath, reader: reader),
           let navData = reader.read(path: navPath, maximumBytes: 8 * 1024 * 1024),
           let parsed = EPUBNavParser.parse(data: navData) {
            tocItems = parsed
            usedEmbedded = !parsed.isEmpty
            if !parsed.isEmpty {
                tocBasePath = navPath
            }
        }

        if tocItems.isEmpty,
           let ncxPath = locateNCXDocument(package: package, packagePath: packagePath, reader: reader),
           let ncxData = reader.read(path: ncxPath, maximumBytes: 8 * 1024 * 1024),
           let parsed = EPUBXMLTOCParser.parse(data: ncxData) {
            tocItems = parsed
            usedEmbedded = !parsed.isEmpty
            if !parsed.isEmpty {
                tocBasePath = ncxPath
            }
        }

        if !tocItems.isEmpty {
            let outline = makeOutline(
                items: tocItems,
                pageCount: pageCount,
                basePath: tocBasePath,
                lookup: lookup,
                lowerBound: 1,
                upperBound: pageCount,
                depth: 1
            )
            if !outline.isEmpty,
               (try? OutlineEditor.validate(outline, pageCount: pageCount)) != nil {
                return DocumentOutlineInfo(
                    pageCount: pageCount,
                    outline: outline,
                    usedEmbeddedOutline: usedEmbedded,
                    warning: nil
                )
            }
        }

        let headingCandidates = headingCandidates(
            reader: reader,
            spinePaths: spinePaths
        )
        let heuristicOutline = DocumentOutlineExtractor.headingOutline(
            from: headingCandidates,
            pageCount: pageCount
        )
        if !heuristicOutline.isEmpty {
            return DocumentOutlineInfo(
                pageCount: pageCount,
                outline: heuristicOutline,
                usedEmbeddedOutline: false,
                warning: nil
            )
        }

        return DocumentOutlineInfo(
            pageCount: pageCount,
            outline: DocumentOutlineExtractor.fallbackOutline(pageCount: pageCount),
            usedEmbeddedOutline: false,
            warning: "EPUB 目录识别失败，已按阅读顺序生成可编辑节点。"
        )
    }

    private static func failure(_ message: String) -> DocumentOutlineInfo {
        DocumentOutlineInfo(
            pageCount: 0,
            outline: [],
            usedEmbeddedOutline: false,
            warning: message
        )
    }

    private static func locatePackagePath(reader: ZIPArchiveReader) -> String? {
        let containerPath = reader.paths.first {
            $0.caseInsensitiveCompare("META-INF/container.xml") == .orderedSame
        }
        if let containerPath,
           let data = reader.read(path: containerPath, maximumBytes: 2 * 1024 * 1024),
           let packagePath = EPUBContainerParser.parse(data: data) {
            return actualArchivePath(packagePath, in: reader)
        }
        return reader.paths.first {
            $0.lowercased().hasSuffix(".opf")
        }
    }

    private static func locateNavigationDocument(
        package: EPUBPackage,
        packagePath: String,
        reader: ZIPArchiveReader
    ) -> String? {
        if let navItem = package.manifest.values.first(where: {
            $0.properties.split(separator: " ").contains("nav")
        }), let resolved = resolveArchivePath(navItem.href, relativeTo: packagePath) {
            return actualArchivePath(resolved, in: reader)
        }
        for candidate in ["nav.xhtml", "toc.xhtml", "navigation.xhtml"] {
            if let match = reader.paths.first(where: {
                ($0 as NSString).lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame
            }) {
                return match
            }
        }
        return nil
    }

    private static func locateNCXDocument(
        package: EPUBPackage,
        packagePath: String,
        reader: ZIPArchiveReader
    ) -> String? {
        if let tocID = package.spineTOC,
           let item = package.manifest[tocID],
           let resolved = resolveArchivePath(item.href, relativeTo: packagePath) {
            return actualArchivePath(resolved, in: reader)
        }
        if let item = package.manifest.values.first(where: {
            $0.mediaType.caseInsensitiveCompare("application/x-dtbncx+xml") == .orderedSame
        }), let resolved = resolveArchivePath(item.href, relativeTo: packagePath) {
            return actualArchivePath(resolved, in: reader)
        }
        if let path = reader.paths.first(where: { $0.lowercased().hasSuffix(".ncx") }) {
            return path
        }
        return nil
    }

    private static func actualArchivePath(_ requested: String, in reader: ZIPArchiveReader) -> String? {
        if reader.contains(requested) {
            return requested
        }
        return reader.paths.first {
            $0.caseInsensitiveCompare(requested) == .orderedSame
        }
    }

    private static func resolveArchivePath(_ link: String, relativeTo basePath: String) -> String? {
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

    private static func normalizeArchivePath(_ path: String) -> String? {
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

    private static func makeOutline(
        items: [EPUBTOCItem],
        pageCount: Int,
        basePath: String,
        lookup: EPUBSpineLookup,
        lowerBound: Int,
        upperBound: Int,
        depth: Int
    ) -> [OutlineNode] {
        guard depth <= OutlineEditor.maximumDepth, lowerBound <= upperBound else {
            return []
        }
        var result: [OutlineNode] = []
        for (index, item) in items.enumerated() {
            let ownPage = resolvePage(
                href: item.href,
                relativeTo: basePath,
                lookup: lookup
            )
            let childStart = item.children.compactMap {
                firstResolvedPage(item: $0, relativeTo: basePath, lookup: lookup, depth: depth + 1)
            }.min()
            let start = min(max(ownPage ?? childStart ?? lowerBound, lowerBound), upperBound)
            let nextStart = items[(index + 1)...].compactMap {
                firstResolvedPage(item: $0, relativeTo: basePath, lookup: lookup, depth: depth + 1)
            }.first
            let end = nextStart.map { min(upperBound, max(start, $0 - 1)) } ?? upperBound
            let children = makeOutline(
                items: item.children,
                pageCount: pageCount,
                basePath: basePath,
                lookup: lookup,
                lowerBound: start,
                upperBound: end,
                depth: depth + 1
            )
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                OutlineNode(
                    title: trimmedTitle.isEmpty ? "未命名章节" : trimmedTitle,
                    startPage: start,
                    endPage: end,
                    children: children
                )
            )
        }
        return result
    }

    private static func firstResolvedPage(
        item: EPUBTOCItem,
        relativeTo basePath: String,
        lookup: EPUBSpineLookup,
        depth: Int
    ) -> Int? {
        guard depth <= OutlineEditor.maximumDepth else {
            return nil
        }
        if let page = resolvePage(href: item.href, relativeTo: basePath, lookup: lookup) {
            return page
        }
        return item.children.compactMap {
            firstResolvedPage(item: $0, relativeTo: basePath, lookup: lookup, depth: depth + 1)
        }.min()
    }

    private static func resolvePage(
        href: String?,
        relativeTo basePath: String,
        lookup: EPUBSpineLookup
    ) -> Int? {
        guard let href,
              let resolved = resolveArchivePath(href, relativeTo: basePath) else {
            return nil
        }
        return lookup.page(for: resolved)
    }

    private static func headingCandidates(
        reader: ZIPArchiveReader,
        spinePaths: [String]
    ) -> [(page: Int, title: String)] {
        var candidates: [(page: Int, title: String)] = []
        let expression = try? NSRegularExpression(
            pattern: "<h([1-3])\\b[^>]*>(.*?)</h\\1\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard let expression else {
            return candidates
        }
        for (offset, path) in spinePaths.enumerated() {
            guard let data = reader.read(path: path, maximumBytes: 2 * 1024 * 1024),
                  let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                continue
            }
            let range = NSRange(html.startIndex..., in: html)
            for match in expression.matches(in: html, range: range) {
                guard let levelRange = Range(match.range(at: 1), in: html),
                      let bodyRange = Range(match.range(at: 2), in: html) else {
                    continue
                }
                let level = Int(html[levelRange]) ?? 3
                let title = stripHTML(String(html[bodyRange]))
                if level == 1 || DocumentOutlineExtractor.looksLikeChapterHeading(title) {
                    candidates.append((offset + 1, title))
                }
            }
        }
        return candidates
    }

    private static func stripHTML(_ source: String) -> String {
        let noTags = source.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return decoded
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private struct EPUBSpineLookup {
    private let exact: [String: Int]
    private let uniqueNames: [String: Int]
    private let duplicateNames: Set<String>

    init(spinePaths: [String]) {
        var exact: [String: Int] = [:]
        var names: [String: [Int]] = [:]
        for (offset, path) in spinePaths.enumerated() {
            exact[path] = offset + 1
            let name = (path as NSString).lastPathComponent.lowercased()
            names[name, default: []].append(offset + 1)
        }
        self.exact = exact
        self.uniqueNames = names.compactMapValues { $0.count == 1 ? $0[0] : nil }
        self.duplicateNames = Set(names.filter { $0.value.count > 1 }.keys)
    }

    func page(for path: String) -> Int? {
        if let page = exact[path] {
            return page
        }
        let name = (path as NSString).lastPathComponent.lowercased()
        return duplicateNames.contains(name) ? nil : uniqueNames[name]
    }
}

private struct EPUBManifestItem {
    let href: String
    let mediaType: String
    let properties: String
}

private struct EPUBPackage {
    let manifest: [String: EPUBManifestItem]
    let spine: [String]
    let spineTOC: String?
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    private var manifest: [String: EPUBManifestItem] = [:]
    private var spine: [String] = []
    private var spineTOC: String?

    static func parse(_ data: Data) -> EPUBPackage? {
        let delegate = EPUBPackageParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return EPUBPackage(manifest: delegate.manifest, spine: delegate.spine, spineTOC: delegate.spineTOC)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "item":
            guard let id = attribute("id", in: attributeDict),
                  let href = attribute("href", in: attributeDict) else {
                return
            }
            manifest[id] = EPUBManifestItem(
                href: href,
                mediaType: attribute("media-type", in: attributeDict) ?? "",
                properties: attribute("properties", in: attributeDict) ?? ""
            )
        case "spine":
            spineTOC = attribute("toc", in: attributeDict)
        case "itemref":
            if let idref = attribute("idref", in: attributeDict) {
                spine.append(idref)
            }
        default:
            break
        }
    }
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private var packagePath: String?

    static func parse(data: Data) -> String? {
        let delegate = EPUBContainerParser()
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
        if localName(elementName) == "rootfile" {
            packagePath = attribute("full-path", in: attributeDict)
        }
    }
}

private final class EPUBTOCItem {
    var title: String
    var href: String?
    var children: [EPUBTOCItem]

    init(title: String = "", href: String? = nil, children: [EPUBTOCItem] = []) {
        self.title = title
        self.href = href
        self.children = children
    }
}

private final class EPUBNavParser: NSObject, XMLParserDelegate {
    private let requireExplicitTOC: Bool
    private var navigationStack: [Bool] = []
    private var listDepth = 0
    private var itemStack: [EPUBTOCItem] = []
    private var roots: [EPUBTOCItem] = []
    private var capturingTitle = false
    private var titleBuffer = ""

    private init(requireExplicitTOC: Bool) {
        self.requireExplicitTOC = requireExplicitTOC
    }

    static func parse(data: Data) -> [EPUBTOCItem]? {
        let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let hasExplicitTOC = source.range(
            of: "epub:type\\s*=\\s*[\"'][^\"']*toc",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let delegate = EPUBNavParser(requireExplicitTOC: hasExplicitTOC)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return delegate.roots.isEmpty ? nil : delegate.roots
        }
        let pruned = delegate.roots.compactMap { prune($0, depth: 1) }
        return pruned.isEmpty ? nil : pruned
    }

    private static func prune(_ item: EPUBTOCItem, depth: Int) -> EPUBTOCItem? {
        guard depth <= OutlineEditor.maximumDepth else {
            return nil
        }
        let children = item.children.compactMap { prune($0, depth: depth + 1) }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty, item.href == nil, children.isEmpty {
            return nil
        }
        return EPUBTOCItem(title: title, href: item.href, children: children)
    }

    private var isInsideTOC: Bool {
        navigationStack.contains(true)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "nav":
            let typeValue = attribute("type", in: attributeDict)?.lowercased() ?? ""
            let isTOC = typeValue.split(separator: " ").contains("toc")
            let treatAsTOC = isTOC || (!requireExplicitTOC && navigationStack.isEmpty)
            navigationStack.append(treatAsTOC)
        case "ol":
            if isInsideTOC {
                listDepth += 1
            }
        case "li":
            guard isInsideTOC,
                  listDepth > 0,
                  itemStack.count < OutlineEditor.maximumDepth else {
                return
            }
            let item = EPUBTOCItem()
            if let parent = itemStack.last {
                parent.children.append(item)
            } else {
                roots.append(item)
            }
            itemStack.append(item)
        case "a":
            guard isInsideTOC, let current = itemStack.last else {
                return
            }
            if current.href == nil {
                current.href = attribute("href", in: attributeDict)
            }
            if current.title.isEmpty {
                capturingTitle = true
                titleBuffer = ""
            }
        case "span":
            guard isInsideTOC,
                  let current = itemStack.last,
                  current.title.isEmpty,
                  current.href == nil,
                  !capturingTitle else {
                return
            }
            capturingTitle = true
            titleBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTitle {
            titleBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(elementName) {
        case "a", "span":
            if capturingTitle {
                let trimmed = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    itemStack.last?.title = trimmed
                }
                capturingTitle = false
                titleBuffer = ""
            }
        case "li":
            if isInsideTOC, !itemStack.isEmpty {
                itemStack.removeLast()
            }
        case "ol":
            if isInsideTOC, listDepth > 0 {
                listDepth -= 1
            }
        case "nav":
            if !navigationStack.isEmpty {
                navigationStack.removeLast()
            }
            if !isInsideTOC {
                listDepth = 0
                itemStack.removeAll()
            }
        default:
            break
        }
    }
}

private final class EPUBXMLTOCParser: NSObject, XMLParserDelegate {
    private var itemStack: [EPUBTOCItem] = []
    private var roots: [EPUBTOCItem] = []
    private var capturingText = false
    private var textBuffer = ""

    static func parse(data: Data) -> [EPUBTOCItem]? {
        let delegate = EPUBXMLTOCParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return delegate.roots.isEmpty ? nil : delegate.roots
        }
        return delegate.roots.isEmpty ? nil : delegate.roots
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "navpoint":
            guard itemStack.count < OutlineEditor.maximumDepth else {
                return
            }
            let item = EPUBTOCItem()
            if let parent = itemStack.last {
                parent.children.append(item)
            } else {
                roots.append(item)
            }
            itemStack.append(item)
        case "text":
            if !itemStack.isEmpty {
                capturingText = true
                textBuffer = ""
            }
        case "content":
            if let source = attribute("src", in: attributeDict),
               itemStack.last?.href == nil {
                itemStack.last?.href = source
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(elementName) {
        case "text":
            if capturingText, let item = itemStack.last, item.title.isEmpty {
                item.title = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            capturingText = false
            textBuffer = ""
        case "navpoint":
            if !itemStack.isEmpty {
                itemStack.removeLast()
            }
        default:
            break
        }
    }
}

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
}

private func attribute(_ key: String, in attributes: [String: String]) -> String? {
    if let direct = attributes[key] {
        return direct
    }
    return attributes.first {
        localName($0.key) == key.lowercased()
    }?.value
}
