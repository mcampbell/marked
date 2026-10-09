public enum LineDiff {
    /// 1-based first line that differs; nil when identical.
    /// Splits UTF-8 bytes on LF: a Character split would treat CRLF as one char.
    public static func firstChangedLine(_ old: String, _ new: String) -> Int? {
        let lf = UInt8(ascii: "\n")
        let a = old.utf8.split(separator: lf, omittingEmptySubsequences: false)
        let b = new.utf8.split(separator: lf, omittingEmptySubsequences: false)
        for (i, (x, y)) in zip(a, b).enumerated() where !x.elementsEqual(y) { return i + 1 }
        return a.count == b.count ? nil : min(a.count, b.count) + 1
    }
}
