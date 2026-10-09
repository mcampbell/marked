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
        return bare?.url == shell ? .allow : .cancel
    }
}
