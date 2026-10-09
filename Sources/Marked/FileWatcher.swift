import Foundation

enum ReadError: Error, CustomStringConvertible {
    case unreadable(String)
    case notUTF8

    var description: String {
        switch self {
        case .unreadable(let reason): reason
        case .notUTF8: "file is not UTF-8 text"
        }
    }
}

enum FileWatcher {
    static func read(_ url: URL) -> Result<String, ReadError> {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        guard let s = String(data: data, encoding: .utf8) else { return .failure(.notUTF8) }
        return .success(s)
    }
}
