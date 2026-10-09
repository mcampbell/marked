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

    private var status: FindStatus?
    private var savedIndex = 0
    private var failed = false
    private var visible = false
    private var ready = false
    private var revision = 0

    public init() {}

    public func open() { visible = true; refresh() }

    public func close() {
        visible = false
        query = ""
        savedIndex = 0
        status = nil
        failed = false
        revision += 1
        if ready { Task { @MainActor in _ = try? await send(.clear) } }
        refresh()
    }

    /// Ignored while closed.
    public func type(_ query: String) {
        guard visible else { return }
        self.query = query
        savedIndex = 0
        status = nil
        failed = false
        if ready { request(query.isEmpty ? .clear : .set(query)) } else { refresh() }
    }

    public func next() { step(1) }
    public func previous() { step(-1) }

    public func shellWillReload() {
        ready = false
        revision += 1
    }

    /// Non-throwing, fire-and-forget. The first call after start or a shell reload restores the search.
    public func renderDidComplete() {
        let first = !ready
        ready = true
        guard visible, !query.isEmpty else { return }
        request(first ? .restore(query, savedIndex) : .state)
    }

    private func step(_ dir: Int) {
        guard visible, ready, !query.isEmpty else { return }
        request(.step(dir))
    }

    private func request(_ cmd: FindCommand) {
        revision += 1
        let rev = revision
        Task { @MainActor in
            let result: FindStatus?
            do { result = try await send(cmd) } catch { result = nil }
            guard rev == revision else { return }
            if let result {
                status = result
                if result.index >= 0 { savedIndex = result.index }
                failed = false
            } else {
                failed = true
            }
            refresh()
        }
        refresh()
    }

    private func refresh() {
        let label: String
        if !visible { label = "" }
        else if failed { label = "Find failed" }
        else if query.isEmpty { label = "" }
        else if let s = status { label = s.count == 0 ? "No results" : "\(s.index + 1) of \(s.count)" }
        else { label = "" }
        let v = visible ? FindView(isVisible: true, label: label) : .hidden
        guard v != view else { return }
        view = v
        onChange(v)
    }
}
