import Testing
@testable import MarkedCore

@Suite struct ImageStampTests {

    func run(_ html: String, _ m: [String: Double] = ["/tmp/d/a.png": 12.0]) -> String {
        ImageStamp.apply(html, shell: .init(string: "marked://doc/tmp/d/__marked__.html")!, mtime: { m[$0] })
    }

    @Test func basicAndUnits() {
        #expect(run(#"<img src="a.png" alt="x" />"#) == #"<img src="a.png?v=12000" alt="x" />"#)
        #expect(run(#"<img src="a.png">"#, ["/tmp/d/a.png": 12.0004]) == #"<img src="a.png?v=12000">"#)
        #expect(run(#"<img src="a.png">"#, ["/tmp/d/a.png": 12.5]) == #"<img src="a.png?v=12500">"#)
    }
    @Test func upAndAbsolute() {
        #expect(run(#"<img src="../up.png">"#, ["/tmp/up.png": 1]) == #"<img src="../up.png?v=1000">"#)
        #expect(run(#"<img src="/abs/p.png">"#, ["/abs/p.png": 1]) == #"<img src="/abs/p.png?v=1000">"#)
    }
    @Test func percentEncoded() {
        #expect(run(#"<img src="a%20b.png">"#, ["/tmp/d/a b.png": 2]) == #"<img src="a%20b.png?v=2000">"#)
    }
    @Test func missingUnchanged() {
        let h = #"<img src="nope.png">"#
        #expect(run(h) == h)
    }
    @Test(arguments: [#"<img src="https://x/a.png">"#, #"<img src="data:image/png;base64,AA">"#,
                      #"<img src="a.png?q=1">"#, #"<img src="a.png#f">"#,
                      "<img src='a.png'>", #"<source src="a.png">"#,
                      "<!-- <img src=\"a.png\"> -->", #"<a title="<img src='a.png'>">"#])
    func unchanged(h: String) {
        #expect(run(h) == h)
    }
    @Test func ampersand() {
        #expect(run(#"<img src="a&amp;b.png">"#, ["/tmp/d/a&b.png": 1]) == #"<img src="a&amp;b.png?v=1000">"#)
    }
    @Test func twoImages() {
        let m = ["/tmp/d/a.png": 1.0, "/tmp/d/b.png": 2.0]
        #expect(run(#"<img src="a.png"><img src="b.png">"#, m) == #"<img src="a.png?v=1000"><img src="b.png?v=2000">"#)
    }
    @Test func dataSrcIgnored() {
        #expect(run(#"<img data-src="other.png" src="a.png">"#, ["/tmp/d/a.png": 1, "/tmp/d/other.png": 9])
                == #"<img data-src="other.png" src="a.png?v=1000">"#)
    }
    @Test func caseInsensitive() {
        #expect(run(#"<IMG SRC="a.png">"#) == #"<IMG SRC="a.png?v=12000">"#)
    }
    @Test func srcInsideOtherAttr() {
        #expect(run(#"<img alt=' src="other.png"' src="a.png">"#) == #"<img alt=' src="other.png"' src="a.png?v=12000">"#)
    }
    @Test func gtInAttr() {
        #expect(run(#"<img alt="a > b" src="a.png">"#) == #"<img alt="a > b" src="a.png?v=12000">"#)
    }
    @Test func newlineBeforeSrc() {
        #expect(run("<img\nsrc=\"a.png\">") == "<img\nsrc=\"a.png?v=12000\">")
    }
}
