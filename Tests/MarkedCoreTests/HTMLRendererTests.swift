import Testing
@testable import MarkedCore

// Frontmatter (S4)
@Test func frontmatterBlock() {
    let h = HTMLRenderer.render("---\ntitle: x\n---\n# H")
    #expect(h.hasPrefix("<pre class=\"frontmatter\" data-sourcepos=\"1:1-3:3\"><code>---\ntitle: x\n---</code></pre>"))
    #expect(h.contains("data-sourcepos=\"4:1-4:3\""))
}
@Test func frontmatterEscapes() {
    let h = HTMLRenderer.render("---\na: <b> & \"c\"\n---\n")
    #expect(h.contains("a: &lt;b&gt; &amp; &quot;c&quot;"))
}
@Test func frontmatterUnclosed() {
    let h = HTMLRenderer.render("---\na: 1\n# H")
    #expect(!h.contains("class=\"frontmatter\""))
    #expect(h.contains("<hr"))
}
@Test func frontmatterEmpty() {
    let h = HTMLRenderer.render("---\n---\n# H")
    #expect(h.hasPrefix("<pre class=\"frontmatter\" data-sourcepos=\"1:1-2:3\"><code>---\n---</code></pre>"))
    #expect(h.contains("data-sourcepos=\"3:1-3:3\""))
}
@Test func frontmatterNotOnLine1() {
    #expect(!HTMLRenderer.render("a\n\n---\nb\n").contains("class=\"frontmatter\""))
}
@Test func frontmatterCRLF() {
    let h = HTMLRenderer.render("---\r\ntitle: x\r\n---\r\n# H\r\n")
    #expect(h.contains("<code>---\ntitle: x\n---</code>"))
    #expect(h.contains("data-sourcepos=\"4:1-4:3\""))
}

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

// Soft line breaks (newline, no blank line) render the same as one line: same HTML, so find matches across them.
private func withoutSourcepos(_ html: String) -> String {
    html.split(separator: " data-sourcepos=\"", omittingEmptySubsequences: false)
        .enumerated()
        .map { $0.offset == 0 ? String($0.element) : String($0.element.drop { $0 != "\"" }.dropFirst()) }
        .joined()
}
@Test func softBreaksRenderLikeOneLine() {
    let oneLine = HTMLRenderer.render("this should render the same as that\n")
    for wrapped in ["this should \nrender the same\nas that\n", "this should\nrender the same\nas that\n",
                    "this should\r\nrender the same\r\nas that\r\n"] {
        #expect(withoutSourcepos(HTMLRenderer.render(wrapped)) == withoutSourcepos(oneLine))
    }
}
@Test func blankLineStillSplitsParagraphs() {
    #expect(HTMLRenderer.render("a\n\nb\n").components(separatedBy: "<p").count == 3)
}
// Hard breaks (two trailing spaces or a trailing backslash) stay forced line breaks, per CommonMark.
@Test func hardBreaksStayLineBreaks() {
    #expect(HTMLRenderer.render("one  \ntwo\n").contains("one<br />\ntwo"))
    #expect(HTMLRenderer.render("one\\\ntwo\n").contains("one<br />\ntwo"))
}
