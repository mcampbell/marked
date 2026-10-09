import Testing
@testable import MarkedCore

@Test func packageBuilds() {
    #expect(RenderResult(ok: true, errors: []).ok)
}
