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
    public init() {}

    public mutating func step(_ probe: Probe, read: () -> Result<String, ReadFailure>) -> [WatchEvent] {
        []
    }
}
