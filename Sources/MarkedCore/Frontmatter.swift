public struct Frontmatter: Equatable, Sendable {
    /// Lines 1…endLine verbatim incl. both fences, joined with "\n", each minus a trailing "\r".
    public let text: String
    /// 1-based line of the closing fence.
    public let endLine: Int
    // Explicit public init: synthesized memberwise inits are internal.
    public init(text: String, endLine: Int) {
        self.text = text
        self.endLine = endLine
    }
}

public enum FrontmatterSplit {
    /// nil when the document has no closed frontmatter block. body = source with lines 1…endLine blanked.
    public static func split(_ source: String) -> (frontmatter: Frontmatter, body: String)? {
        var src = Substring(source)
        if src.unicodeScalars.first == "\u{FEFF}" { src.unicodeScalars.removeFirst() }
        // Split UTF-8 bytes: a String split on "\n" would treat CRLF as one Character.
        let lines = src.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        func trim(_ s: String) -> String { s.utf8.last == 13 ? String(s.dropLast()) : s }
        guard lines.count > 1, trim(lines[0]) == "---",
              let close = lines.dropFirst().firstIndex(where: { ["---", "..."].contains(trim($0)) })
        else { return nil }
        let endLine = close + 1
        let text = lines[..<endLine].map(trim).joined(separator: "\n")
        let body = (Array(repeating: "", count: endLine) + lines[endLine...]).joined(separator: "\n")
        return (Frontmatter(text: text, endLine: endLine), body)
    }
}
