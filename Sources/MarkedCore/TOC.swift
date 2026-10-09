import Foundation

/// One sidebar row: a heading as sent by `Marked.toc.headings()`.
public struct TOCEntry: Equatable, Sendable {
    public let level: Int      // 1…6
    public let text: String    // collapsed and trimmed by JS
    public let depth: Int      // level − smallest level in the doc
    public var title: String { text.isEmpty ? "—" : text }
}

public struct TOCError: Error, CustomStringConvertible {
    public let raw: String
    public let source: String
    public let expected: String
    public var description: String { "\(source) returned \(raw); expected \(expected)" }

    public init(raw: String, source: String = "Marked.toc.headings", expected: String = "[{level: 1…6, text}]") {
        (self.raw, self.source, self.expected) = (raw, source, expected)
    }
}

public enum TOC {
    /// Validates the bridge payload. `import Foundation` lets the app's `NSNumber` levels cast with `as? Int`.
    public static func parse(_ raw: Any?) throws -> [TOCEntry] {
        let bad = TOCError(raw: raw.map { "\($0)" } ?? "nil")
        guard let items = raw as? [Any] else { throw bad }
        let pairs = try items.map { item -> (Int, String) in
            guard let d = item as? [String: Any], let level = d["level"] as? Int, (1...6).contains(level),
                  let text = d["text"] as? String else { throw bad }
            return (level, text)
        }
        let top = pairs.map(\.0).min() ?? 1
        return pairs.map { TOCEntry(level: $0.0, text: $0.1, depth: $0.0 - top) }
    }

    /// Scroll-spy payload: integer ≥ -1; -1 → nil (no mark). Range is checked at display: the post can name
    /// a row that only exists after the next `refreshTOC` (S13). JS `true` bridges to an NSNumber that casts
    /// to 1, so CF Booleans are rejected first.
    public static func current(_ raw: Any?) throws -> Int? {
        let bad = TOCError(raw: raw.map { "\($0)" } ?? "nil", source: "toc spy post", expected: "an integer ≥ -1")
        guard let raw, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(),
              let i = raw as? Int, i >= -1 else { throw bad }
        return i == -1 ? nil : i
    }
}
