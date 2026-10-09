import Foundation

public enum DocURL {
    public static let scheme = "marked"
    public static let appHost = "app"
    public static let docHost = "doc"
    public static let shellName = "__marked__.html"

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
        c.scheme = scheme
        c.host = docHost
        c.percentEncodedPath = "/" + (parts + [shellName]).joined(separator: "/")
        return c.url!
    }

    public static func appURL(_ name: String) -> URL {
        URL(string: "\(scheme)://\(appHost)/\(name)")!
    }

    public static func filePath(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == docHost else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
}
