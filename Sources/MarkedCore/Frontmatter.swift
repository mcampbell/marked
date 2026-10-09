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
    /// nil when the document has no closed frontmatter block. body = source with lines 1…endLine blanked. W4 stub.
    public static func split(_ source: String) -> (frontmatter: Frontmatter, body: String)? {
        nil
    }
}
