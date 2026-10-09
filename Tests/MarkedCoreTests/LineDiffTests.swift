import Testing
@testable import MarkedCore

struct LineDiffTests {
    @Test func identical() { #expect(LineDiff.firstChangedLine("a\nb", "a\nb") == nil) }
    @Test func line1() { #expect(LineDiff.firstChangedLine("a\nb", "x\nb") == 1) }
    @Test func line5of10() {
        let old = (1...10).map { "l\($0)" }
        var new = old
        new[4] = "changed"
        #expect(LineDiff.firstChangedLine(old.joined(separator: "\n"), new.joined(separator: "\n")) == 5)
    }
    @Test func append() { #expect(LineDiff.firstChangedLine("a\nb", "a\nb\nc") == 3) }
    @Test func deleteLast() { #expect(LineDiff.firstChangedLine("a\nb\nc", "a\nb") == 3) }
    @Test func whitespaceOnly() { #expect(LineDiff.firstChangedLine("a\nb\nc", "a\nb \nc") == 2) }
    @Test func emptyToA() { #expect(LineDiff.firstChangedLine("", "a") == 1) }
    @Test func trailingNewline() { #expect(LineDiff.firstChangedLine("a\nb", "a\nb\n") == 3) }
    @Test func crlfVsLf() { #expect(LineDiff.firstChangedLine("a\r\nb", "a\nb") == 1) }
    @Test func crlfEdit() { #expect(LineDiff.firstChangedLine("a\r\nb\r\nc", "a\r\nx\r\nc") == 2) }
}
