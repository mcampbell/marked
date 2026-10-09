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
        #expect(DocURL.filePath(from: .init(string: "https://doc/tmp/x.png")!) == nil)
    }

    private func serve(_ url: String, _ info: FileInfo?, _ seen: inout [String]) -> String? {
        var got: [String] = []
        let r = DocURL.imageFile(for: .init(string: url)!) { got.append($0); return info }
        seen = got
        return r
    }
    private func reg(_ p: String) -> FileInfo { .init(resolvedPath: p, isRegularFile: true) }

    @Test func serveRegular() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/a.png", reg("/tmp/a.png"), &seen) == "/tmp/a.png")
        #expect(seen == ["/tmp/a.png"])
    }

    @Test func serveDecodesPath() {
        var seen: [String] = []
        _ = serve("marked://doc/tmp/a%20b/c.png", reg("/tmp/a b/c.png"), &seen)
        #expect(seen == ["/tmp/a b/c.png"])
    }

    @Test func serveUpperExt() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/A.PNG", reg("/tmp/A.PNG"), &seen) == "/tmp/A.PNG")
    }

    @Test(arguments: ["marked://doc/tmp/a.md", "marked://doc/tmp/a.txt", "marked://doc/tmp/a"])
    func serveBadExt(url: String) {
        var seen: [String] = []
        #expect(serve(url, reg("/tmp/a"), &seen) == nil)
        #expect(seen.isEmpty)
    }

    @Test func serveMissing() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/a.png", nil, &seen) == nil)
    }

    @Test func serveDirectory() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/x.png", .init(resolvedPath: "/tmp/x.png", isRegularFile: false), &seen) == nil)
    }

    @Test func serveSymlinkToNonImage() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/a.png", reg("/Users/x/.ssh/id_rsa"), &seen) == nil)
    }

    @Test func serveReservedShell() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/__marked__.html", reg("/tmp/__marked__.html"), &seen) == nil)
    }

    @Test func serveIgnoresQuery() {
        var seen: [String] = []
        #expect(serve("marked://doc/tmp/a.png?v=12", reg("/tmp/a.png"), &seen) == "/tmp/a.png")
        #expect(seen == ["/tmp/a.png"])
    }

    @Test(arguments: ["marked://app/tmp/a.png", "https://doc/tmp/a.png"])
    func serveForeign(url: String) {
        var seen: [String] = []
        #expect(serve(url, reg("/tmp/a.png"), &seen) == nil)
    }

    @Test func mime() {
        #expect(DocURL.contentType(forPath: "/x/a.svg") == "image/svg+xml")
        #expect(DocURL.contentType(forPath: "/x/a.png") == "image/png")
        #expect(DocURL.contentType(forPath: "/x/a.JPG") == "image/jpeg")
    }

    @Test func serveExtensionFromFileNameOnly() {
        let probe: (String) -> FileInfo? = { FileInfo(resolvedPath: $0, isRegularFile: true) }
        #expect(DocURL.imageFile(for: .init(string: "marked://doc/tmp/v1.png/noext")!, probe: probe) == nil)
        #expect(DocURL.imageFile(for: .init(string: "marked://doc/tmp/a.b/c.PNG")!, probe: probe) == "/tmp/a.b/c.PNG")
    }
}
