public enum Style: String, CaseIterable, Sendable {
    case mono, serif, sans

    public static let `default`: Style = .sans

    /// Unknown or nil stored value → sans.
    public init(stored: String?) {
        self = Style(rawValue: stored ?? "") ?? .sans
    }

    public var title: String {
        switch self {
        case .mono: "Monospace"
        case .serif: "Serif"
        case .sans: "Sans-serif"
        }
    }

    public var shortcut: Character {
        switch self {
        case .mono: "1"
        case .serif: "2"
        case .sans: "3"
        }
    }

    public var resource: String { rawValue }
}
