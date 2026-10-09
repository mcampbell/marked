import Testing
@testable import MarkedCore

struct TOCTests {
    private func h(_ level: Any, _ text: Any = "x") -> [String: Any] { ["level": level, "text": text] }

    @Test func empty() throws {
        #expect(try TOC.parse([[String: Any]]()) == [])
    }

    @Test func depthFromSmallestLevel() throws {
        #expect(try TOC.parse([h(2), h(3)]).map(\.depth) == [0, 1])
        #expect(try TOC.parse((1...6).map { h($0) }).map(\.depth) == [0, 1, 2, 3, 4, 5])
        #expect(try TOC.parse([h(2), h(4)]).map(\.depth) == [0, 2])
        #expect(try TOC.parse([h(3), h(1), h(2)]).map(\.depth) == [2, 0, 1])
    }

    @Test func textKeptVerbatim() throws {
        #expect(try TOC.parse([h(1, "Café 日本"), h(2, "C++ & Go!")]).map(\.text) == ["Café 日本", "C++ & Go!"])
    }

    @Test func titleDashWhenEmpty() throws {
        let e = try TOC.parse([h(1, ""), h(2, "a")])
        #expect(e[0].text == "")
        #expect(e[0].title == "—")
        #expect(e[1].title == "a")
    }

    @Test func orderKept() throws {
        #expect(try TOC.parse([h(1, "a"), h(2, "b"), h(1, "c")]).map(\.text) == ["a", "b", "c"])
        #expect(try TOC.parse([h(1, "a"), h(2, "b"), h(1, "c")]).map(\.level) == [1, 2, 1])
    }

    @Test func rejectsBadPayload() {
        let bad: [Any?] = [
            nil, "x", [1], [["text": "a"]], [h(0)], [h(7)], [h("1")], [h(1.5)], [["level": 1]], [h(1, 5)],
        ]
        for raw in bad {
            #expect(throws: TOCError.self, "\(String(describing: raw))") { try TOC.parse(raw) }
        }
    }
}
