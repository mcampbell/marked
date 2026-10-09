import Testing
@testable import MarkedCore

@Suite struct LinkPolicyTests {
    private let dir = "marked://doc/Users/me/My%20Docs/"
    private func decide(_ s: String, click: Bool = true) -> LinkAction {
        LinkPolicy.decide(.init(string: s)!, shell: .init(string: dir + "__marked__.html")!, linkActivated: click)
    }
    // No Foundation import: tests cannot name URL, so compare kind + path/string.
    private func desc(_ a: LinkAction) -> String {
        switch a {
        case .allow: "allow"
        case .cancel: "cancel"
        case .openExternal(let u): "ext " + u.absoluteString
        case .openDocument(let u): "doc " + u.absoluteString
        case .reveal(let u): "reveal " + u.absoluteString
        }
    }

    @Test(arguments: [true, false])
    func shellAllowed(click: Bool) {
        #expect(decide(dir + "__marked__.html", click: click) == .allow)
        #expect(decide(dir + "__marked__.html#x", click: click) == .allow)
    }

    @Test(arguments: ["https://e.com", "http://e.com", "mailto:a@b.c"])
    func external(s: String) {
        #expect(desc(decide(s)) == "ext " + s)
        #expect(decide(s, click: false) == .cancel)
    }

    @Test func externalSchemeIsCaseInsensitive() {
        #expect(desc(decide("HTTPS://e.com")).hasPrefix("ext "))
    }

    @Test(arguments: [
        ("b.md", "/Users/me/My%20Docs/b.md"), ("B.MD", "/Users/me/My%20Docs/B.MD"),
        ("b.markdown", "/Users/me/My%20Docs/b.markdown"), ("b.mdown", "/Users/me/My%20Docs/b.mdown"),
        ("b.md#sec", "/Users/me/My%20Docs/b.md"), ("b.md?x=1", "/Users/me/My%20Docs/b.md"),
        ("sub%20dir/c.md", "/Users/me/My%20Docs/sub%20dir/c.md"), ("a%23b.md", "/Users/me/My%20Docs/a%23b.md"),
    ])
    func openDocument(rel: String, path: String) {
        #expect(desc(decide(dir + rel)) == "doc file://" + path)
        #expect(decide(dir + rel, click: false) == .cancel)
    }

    @Test(arguments: ["notes.txt", "report.pdf", "Tool.app"])
    func reveal(name: String) {
        #expect(desc(decide(dir + name)) == "reveal file:///Users/me/My%20Docs/" + name)
        #expect(decide(dir + name, click: false) == .cancel)
    }

    @Test(arguments: ["file:///etc/hosts", "javascript:alert(1)", "data:text/html,x",
                      "marked://app/base.css", "marked://doc/other/__marked__.html"])
    func cancelled(s: String) {
        #expect(decide(s) == .cancel)
    }
}
