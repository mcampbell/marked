import Testing
@testable import MarkedCore

struct TextSizeTests {
    @Test func stepsTenPoints() {
        #expect(TextSize.step(100, by: 1) == 110)
        #expect(TextSize.step(100, by: -1) == 90)
        #expect(TextSize.step(TextSize.step(100, by: 1), by: -1) == TextSize.normal)
    }

    @Test func clampsToRange() {
        #expect(TextSize.step(300, by: 1) == 300)
        #expect(TextSize.step(50, by: -1) == 50)
        #expect(TextSize.step(295, by: 1) == 300)
    }

    @Test func labelHiddenAtNormal() {
        #expect(TextSize.label(TextSize.normal) == nil)
    }

    @Test func labelShowsPercentOtherwise() {
        #expect(TextSize.label(110) == "110%")
        #expect(TextSize.label(50) == "50%")
    }
}
