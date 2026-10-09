import Foundation
import MarkedCore

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

@MainActor
final class FileWatcher {
    private let url: URL
    private let interval: TimeInterval
    private let onEvent: (WatchEvent) -> Void

    init(url: URL, interval: TimeInterval = 0.5, onEvent: @escaping (WatchEvent) -> Void) {
        self.url = url
        self.interval = interval
        self.onEvent = onEvent
    }

    /// W1 stub: one real read, no polling (keeps S0 behavior until Q2 lands).
    func start() {
        switch Self.read(url) {
        case .success(let text): onEvent(.text(text))
        case .failure(let e): onEvent(.error(e.description))
        }
    }

    func stop() {}

    static func read(_ url: URL) -> Result<String, ReadError> {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        guard let s = String(data: data, encoding: .utf8) else { return .failure(.notUTF8) }
        return .success(s)
    }
}
