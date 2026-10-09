import Foundation

public enum LinkAction: Equatable, Sendable {
    case allow, cancel
    /// File URLs for `openDocument` and `reveal`.
    case openExternal(URL), openDocument(URL), reveal(URL)
}

/// Navigation rules for links in a rendered document (design.md "S6 navigation rules"). First match wins.
public enum LinkPolicy {
    public static func decide(_ url: URL, shell: URL, linkActivated: Bool) -> LinkAction {
        var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
        bare?.fragment = nil
        if bare?.url == shell { return .allow }
        guard linkActivated else { return .cancel }
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto": return .openExternal(url)
        case DocURL.scheme:
            guard let path = DocURL.filePath(from: url), !path.hasSuffix("/" + DocURL.shellName) else { return .cancel }
            let file = URL(fileURLWithPath: path, isDirectory: false)   // no disk probe: decide stays pure
            return ["md", "markdown", "mdown"].contains(file.pathExtension.lowercased()) ? .openDocument(file) : .reveal(file)
        default: return .cancel
        }
    }
}
