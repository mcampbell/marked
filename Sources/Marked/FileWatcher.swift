import Foundation

enum ReadError: Error {
    case unreadable(String)
    case notUTF8
}

enum FileWatcher {
    static func read(_ url: URL) -> Result<String, ReadError> {
        .success("stub")
    }
}
