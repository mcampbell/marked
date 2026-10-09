@MainActor
public final class RenderQueue {
    public var changedLine: (String, String) -> Int? = { _, _ in nil }
    public var onFailure: (Error) -> Void = { _ in }

    private let render: (String) -> String
    private let send: (String, Int?) async throws -> RenderResult

    public init(
        render: @escaping (String) -> String,
        send: @escaping (String, Int?) async throws -> RenderResult
    ) {
        self.render = render
        self.send = send
    }

    public func submit(_ source: String) {}
    public func markReady() {}
    public func shellWillReload() {}
}
