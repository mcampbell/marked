import Testing
@testable import MarkedCore

@Suite struct DocURLTests {
    @Test(arguments: ["/tmp/a b", "/tmp/a#b", "/tmp/a?b", "/tmp/a%20b", "/tmp/é", "/tmp/a;b"])
    func roundTrip(dir: String) {
        let u = DocURL.shellURL(forDocument: .init(fileURLWithPath: dir + "/x.md"))
        #expect(DocURL.filePath(from: u) == dir + "/__marked__.html")
        #expect(u.absoluteString.hasSuffix("/__marked__.html"))
        #expect(!u.absoluteString.contains(" "))
        #expect(!u.absoluteString.contains("#"))
    }

    @Test func appURLs() {
        let u = DocURL.appURL("base.css")
        #expect(u.absoluteString == "marked://app/base.css")
        #expect(DocURL.filePath(from: u) == nil)
    }
}
