import Foundation

public enum DocURL {
    private static let allowed: CharacterSet = {
        var s = CharacterSet.urlPathAllowed
        s.remove(charactersIn: "#?;/")
        return s
    }()

    public static func shellURL(forDocument document: URL) -> URL {
        let dir = document.deletingLastPathComponent().path
        let parts = dir.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: allowed)!
        }
        var c = URLComponents()
        c.scheme = "marked"
        c.host = "doc"
        c.percentEncodedPath = "/" + (parts + ["__marked__.html"]).joined(separator: "/")
        return c.url!
    }

    public static func appURL(_ name: String) -> URL {
        URL(string: "marked://app/\(name)")!
    }

    public static func filePath(from url: URL) -> String? {
        guard url.scheme == "marked", url.host == "doc" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
