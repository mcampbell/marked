public enum Style: String, CaseIterable, Sendable {
    case mono, serif, sans

    public static let `default`: Style = .sans

    /// Unknown or nil stored value → sans. W2 stub.
    public init(stored: String?) {
        self = .sans
    }

    /// W2 stub.
    public var title: String { rawValue }
    /// W2 stub.
    public var shortcut: Character { "0" }
    /// W2 stub.
    public var resource: String { rawValue }
}
