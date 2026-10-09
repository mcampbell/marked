public struct Stamp: Equatable, Sendable {
    public let mtime: Double
    public let size: Int
    // Public inits are explicit: synthesized memberwise inits are internal, and the app target builds these.
    public init(mtime: Double, size: Int) {
        self.mtime = mtime
        self.size = size
    }
}

public enum Probe: Equatable, Sendable {
    case missing
    case present(Stamp)
}

public enum WatchEvent: Equatable, Sendable {
    case text(String)
    case error(String)
    case cleared
}

public struct ReadFailure: Error, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
}

public struct WatchState {
    private var lastStamp: Stamp?
    private var lastText: String?
    private var showingError: String?
    private var missing = 0

    public init() {}

    public mutating func step(_ probe: Probe, read: () -> Result<String, ReadFailure>) -> [WatchEvent] {
        switch probe {
        case .missing:
            lastStamp = nil
            missing += 1
            return missing >= 2 ? fail("File not found") : []
        case .present(let stamp):
            missing = 0
            guard stamp != lastStamp || showingError != nil else { return [] }
            lastStamp = stamp
            switch read() {
            case .failure(let e):
                return fail(e.message)
            case .success(let text):
                var events: [WatchEvent] = []
                if showingError != nil { showingError = nil; events.append(.cleared) }
                if text != lastText { lastText = text; events.append(.text(text)) }
                return events
            }
        }
    }

    private mutating func fail(_ msg: String) -> [WatchEvent] {
        guard msg != showingError else { return [] }
        showingError = msg
        return [.error(msg)]
    }
}
