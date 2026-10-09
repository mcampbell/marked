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

    private var timer: Timer?
    private var state = WatchState()

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let url = url
        let probe: Probe
        if let a = try? FileManager.default.attributesOfItem(atPath: url.path) {
            probe = .present(Stamp(
                mtime: (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                size: (a[.size] as? NSNumber)?.intValue ?? 0))
        } else {
            probe = .missing
        }
        for e in state.step(probe, read: {
            Self.read(url).mapError { ReadFailure(message: $0.description) }
        }) { onEvent(e) }
    }

    static func read(_ url: URL) -> Result<String, ReadError> {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        guard let s = String(data: data, encoding: .utf8) else { return .failure(.notUTF8) }
        return .success(s)
    }
}
