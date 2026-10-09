import Foundation

public enum ImageStamp {
    private static let attr = #"\s+([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?"#
    // Quote-aware tag scan: comments and quoted attribute values are consumed whole.
    private static let tagRe = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<([A-Za-z][^\s/>]*)((?:"# + attr + #")*)\s*/?>"#)
    private static let attrRe = try! NSRegularExpression(pattern: attr)

    /// Appends ?v=<mtime ms> to each local double-quoted <img src>; mtime(path) nil leaves src as is.
    public static func apply(_ html: String, shell: URL, mtime: (String) -> Double?) -> String {
        let ns = html as NSString
        var out = html
        var edits: [(NSRange, String)] = []
        for m in tagRe.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let nameR = m.range(at: 1)
            guard nameR.location != NSNotFound, ns.substring(with: nameR).lowercased() == "img" else { continue }
            let attrs = m.range(at: 2)
            for a in attrRe.matches(in: html, range: attrs) {
                guard ns.substring(with: a.range(at: 1)).lowercased() == "src" else { continue }
                let v = a.range(at: 2)
                if v.location != NSNotFound {
                    let value = ns.substring(with: v)
                    if let s = stamp(value, shell: shell, mtime: mtime) { edits.append((v, s)) }
                }
                break // first src only
            }
        }
        for (r, s) in edits.reversed() {
            out = (out as NSString).replacingCharacters(in: r, with: s)
        }
        return out
    }

    private static func stamp(_ value: String, shell: URL, mtime: (String) -> Double?) -> String? {
        guard !value.contains("?"), !value.contains("#"),
              let url = URL(string: value.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: shell)?.absoluteURL,
              let path = DocURL.filePath(from: url),
              let t = mtime(path) else { return nil }
        return value + "?v=\(Int(t * 1000))"
    }
}
