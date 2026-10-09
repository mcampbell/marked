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
