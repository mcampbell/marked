import Foundation

public enum DocURL {
    public static func shellURL(forDocument document: URL) -> URL {
        URL(string: "marked://doc/__marked__.html")!
    }

    public static func appURL(_ name: String) -> URL {
        URL(string: "marked://app/\(name)")!
    }

    public static func filePath(from url: URL) -> String? {
        nil
    }
}
