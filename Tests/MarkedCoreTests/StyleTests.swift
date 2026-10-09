import Testing
@testable import MarkedCore

struct StyleTests {
    @Test func allCasesOrder() {
        #expect(Style.allCases == [.mono, .serif, .sans])
    }

    @Test func shortcuts() {
        #expect(Style.allCases.map(\.shortcut) == ["1", "2", "3"])
        #expect(Set(Style.allCases.map(\.shortcut)).count == 3)
    }

    @Test func titles() {
        #expect(Style.allCases.map(\.title) == ["Monospace", "Serif", "Sans-serif"])
    }

    @Test func resourcesMatchRawValues() {
        for s in Style.allCases { #expect(s.resource == s.rawValue) }
        #expect(Style.allCases.map(\.resource) == ["mono", "serif", "sans"])
    }

    @Test func defaultIsSans() {
        #expect(Style.default == .sans)
    }

    @Test func initStored() {
        #expect(Style(stored: "serif") == .serif)
        #expect(Style(stored: nil) == .sans)
        #expect(Style(stored: "bogus") == .sans)
    }
}
