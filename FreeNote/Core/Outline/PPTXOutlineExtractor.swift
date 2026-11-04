import Foundation

enum PPTXOutlineExtractor {
    static func inspect(url: URL) -> DocumentOutlineInfo {
        guard url.pathExtension.lowercased() == "pptx" else {
            return singlePageFallback("该 Office 文件暂不解析内嵌目录。")
        }
        guard let reader = try? ZIPArchiveReader(url: url) else {
            return singlePageFallback("无法安全读取 PPTX 压缩包。")
        }

        let expression = try? NSRegularExpression(
            pattern: "^ppt/slides/slide([0-9]+)\\.xml$",
            options: [.caseInsensitive]
        )
        guard let expression else {
            return singlePageFallback("PPTX 文件名解析失败。")
        }
        var slides: [(page: Int, path: String, number: Int)] = []
        for path in reader.paths {
            let range = NSRange(path.startIndex..., in: path)
            guard let match = expression.firstMatch(in: path, range: range),
                  let numberRange = Range(match.range(at: 1), in: path),
                  let number = Int(path[numberRange]) else {
                continue
            }
            slides.append((0, path, number))
        }
        slides.sort { $0.number < $1.number }
        guard !slides.isEmpty else {
            return singlePageFallback("PPTX 中没有识别到幻灯片。")
        }

        let pageCount = slides.count
        let titles: [String] = slides.enumerated().map { offset, slide in
            guard let data = reader.read(path: slide.path, maximumBytes: 8 * 1024 * 1024),
                  let xml = String(data: data, encoding: .utf8) else {
                return "第 \(offset + 1) 页"
            }
            return extractTitle(from: xml) ?? "第 \(offset + 1) 页"
        }

        let sectionCandidates = titles.enumerated().compactMap { offset, title in
            DocumentOutlineExtractor.looksLikeChapterHeading(title)
                ? (page: offset + 1, title: title)
                : nil
        }
        if !sectionCandidates.isEmpty {
            let outline = DocumentOutlineExtractor.headingOutline(
                from: sectionCandidates,
                pageCount: pageCount
            )
            return DocumentOutlineInfo(
                pageCount: pageCount,
                outline: outline,
                usedEmbeddedOutline: false,
                warning: nil
            )
        }

        return DocumentOutlineInfo(
            pageCount: pageCount,
            outline: DocumentOutlineExtractor.fallbackOutline(pageCount: pageCount, titles: titles),
            usedEmbeddedOutline: false,
            warning: nil
        )
    }

    private static func singlePageFallback(_ warning: String?) -> DocumentOutlineInfo {
        DocumentOutlineInfo(
            pageCount: 1,
            outline: DocumentOutlineExtractor.fallbackOutline(pageCount: 1),
            usedEmbeddedOutline: false,
            warning: warning
        )
    }

    private static func extractTitle(from xml: String) -> String? {
        let titlePattern = "<p:ph\\b[^>]*type\\s*=\\s*[\"'](?:title|ctrTitle)[\"'][^>]*>(.*?)</p:ph>"
        if let titleBlock = firstMatch(in: xml, pattern: titlePattern),
           let text = firstMatch(in: titleBlock, pattern: "<a:t\\b[^>]*>(.*?)</a:t>") {
            let cleaned = cleanXMLText(text)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        if let fallback = firstMatch(in: xml, pattern: "<a:t\\b[^>]*>(.*?)</a:t>") {
            let cleaned = cleanXMLText(fallback)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    private static func firstMatch(in source: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = expression.firstMatch(in: source, range: range),
              let captureRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[captureRange])
    }

    private static func cleanXMLText(_ source: String) -> String {
        let stripped = source.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
