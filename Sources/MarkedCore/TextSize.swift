/// Per-window text size in percent (D50). Cmd-plus / Cmd-minus step 10 points; Cmd-0 resets.
public enum TextSize {
    public static let normal = 100
    public static let range = 50...300

    /// `percent` moved by `steps` × 10, kept inside `range`.
    public static func step(_ percent: Int, by steps: Int) -> Int {
        min(max(percent + steps * 10, range.lowerBound), range.upperBound)
    }
}
