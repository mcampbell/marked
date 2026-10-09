import Testing
@testable import MarkedCore

@Test func headingSourcepos() {
    #expect(HTMLRenderer.render("# Hi").contains("data-sourcepos=\"1:1-1:4\""))
}
@Test func table() {
    #expect(HTMLRenderer.render("|a|b|\n|-|-|\n|1|2|\n").contains("<table"))
}
@Test func strike() {
    #expect(HTMLRenderer.render("~~x~~").contains("<del>"))
}
@Test func tasklist() {
    #expect(HTMLRenderer.render("- [ ] a").contains("type=\"checkbox\""))
}
@Test func rawHTML() {
    let h = "<details><summary>s</summary>b</details>"
    #expect(HTMLRenderer.render(h).contains(h))
}
@Test func empty() {
    #expect(HTMLRenderer.render("") == "")
}

// Marked 2 renders `==` as a highlight even inside code. Here `==` must stay literal in code.
@Test func doubleEqualsLiteralInFencedCode() {
    let h = HTMLRenderer.render("```\nif a == b { x ==y== }\n```\n")
    #expect(h.contains("if a == b { x ==y== }"))
    #expect(!h.contains("<mark"))
}
@Test func doubleEqualsLiteralInInlineCode() {
    let h = HTMLRenderer.render("Use `a == b` and `==x==`.")
    #expect(h.contains("<code>a == b</code>"))
    #expect(h.contains("<code>==x==</code>"))
    #expect(!h.contains("<mark"))
}
