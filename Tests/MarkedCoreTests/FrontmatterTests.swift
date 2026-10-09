import Testing
@testable import MarkedCore

struct FrontmatterTests {
    @Test func basic() {
        let r = FrontmatterSplit.split("---\ntitle: x\n---\n# H")
        #expect(r?.frontmatter.text == "---\ntitle: x\n---")
        #expect(r?.frontmatter.endLine == 3)
        #expect(r?.body == "\n\n\n# H")
    }
    @Test func dotsClose() {
        let r = FrontmatterSplit.split("---\na\n...\nx")
        #expect(r?.frontmatter.text == "---\na\n...")
    }
    @Test func unclosed() { #expect(FrontmatterSplit.split("---\na: 1\n# H") == nil) }
    @Test func notLine1() { #expect(FrontmatterSplit.split("\n---\na\n---") == nil) }
    @Test func badFences() {
        #expect(FrontmatterSplit.split("--- \na\n---") == nil)
        #expect(FrontmatterSplit.split(" ---\na\n---") == nil)
    }
    @Test func crlf() {
        let r = FrontmatterSplit.split("---\r\na: 1\r\n---\r\n# H")
        #expect(r?.frontmatter.text == "---\na: 1\n---")
        #expect(r?.frontmatter.endLine == 3)
        #expect(r?.body == "\n\n\n# H")
    }
    @Test func bom() {
        let r = FrontmatterSplit.split("\u{FEFF}---\na\n---")
        #expect(r?.frontmatter.text == "---\na\n---")
    }
    @Test func empty() {
        let r = FrontmatterSplit.split("---\n---\nx")
        #expect(r?.frontmatter.text == "---\n---")
        #expect(r?.frontmatter.endLine == 2)
    }
    @Test func firstCloseWins() {
        #expect(FrontmatterSplit.split("---\na\n---\nb\n---")?.frontmatter.endLine == 3)
    }
    @Test func unescaped() {
        let r = FrontmatterSplit.split("---\na: <b> & c\nd\n---")
        #expect(r?.frontmatter.text == "---\na: <b> & c\nd\n---")
    }
    @Test func lineCount() {
        let s = "---\na\n---\nb\n\nc\n"
        let r = FrontmatterSplit.split(s)
        #expect(r?.body.utf8.filter { $0 == 10 }.count == s.utf8.filter { $0 == 10 }.count)
    }
}
