/// Wire shape from `Marked.render`: `{ok: boolean, errors: string[]}`,
/// each error `"<hook name>: <message>"`.
public struct RenderResult: Sendable, Equatable {
    public let ok: Bool
    public let errors: [String]

    public init(ok: Bool, errors: [String]) {
        self.ok = ok
        self.errors = errors
    }
}
