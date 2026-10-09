public struct FindStatus: Equatable, Sendable {
    public let count: Int
    /// -1 when there is no current match.
    public let index: Int
    public init(count: Int, index: Int) { self.count = count; self.index = index }
    public static let empty = FindStatus(count: 0, index: -1)
}

public enum FindCommand: Equatable, Sendable {
    case set(String), step(Int), restore(String, Int), clear, state
}

/// What the find bar shows. Label: "" | "No results" | "3 of 12" | "Find failed".
public struct FindView: Equatable, Sendable {
    public let isVisible: Bool
    public let label: String
    public init(isVisible: Bool, label: String) { self.isVisible = isVisible; self.label = label }
    public static let hidden = FindView(isVisible: false, label: "")
}

public struct FindBridgeNotWired: Error {}

@MainActor
public final class FindSession {
    public var send: (FindCommand) async throws -> FindStatus = { _ in throw FindBridgeNotWired() }
    public var onChange: (FindView) -> Void = { _ in }
    public private(set) var view = FindView.hidden
    public private(set) var query = ""

    public init() {}

    public func open() {}
    public func close() {}
    /// Ignored while closed.
    public func type(_ query: String) {}
    public func next() {}
    public func previous() {}
    public func shellWillReload() {}
    /// Non-throwing, fire-and-forget. The first call after start or a shell reload restores the search.
    public func renderDidComplete() {}
}
