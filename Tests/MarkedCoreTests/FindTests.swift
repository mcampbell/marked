import Testing
@testable import MarkedCore

@MainActor
final class FakeFind {
    var cmds: [FindCommand] = []
    var waiting: [CheckedContinuation<FindStatus, Error>] = []
    var immediate: Result<FindStatus, Error>?

    func send(_ c: FindCommand) async throws -> FindStatus {
        cmds.append(c)
        if let r = immediate { return try r.get() }
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func resume(_ s: FindStatus) async { waiting.removeFirst().resume(returning: s); await settle() }
    func fail() async { waiting.removeFirst().resume(throwing: Boom()); await settle() }
}

@MainActor
func makeFind(_ f: FakeFind, ready: Bool = true) -> FindSession {
    let s = FindSession()
    s.send = { try await f.send($0) }
    if ready { s.renderDidComplete() }
    return s
}

@MainActor
@Suite struct FindTests {
    @Test func closedTypeSendsNothing() async {
        let f = FakeFind(); let s = makeFind(f)
        s.type("a"); await settle()
        #expect(f.cmds.isEmpty)
    }

    @Test func openTypeSetsThenLabel() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); await settle()
        #expect(f.cmds == [.set("a")])
        #expect(s.view == FindView(isVisible: true, label: ""))
        await f.resume(FindStatus(count: 3, index: 0))
        #expect(s.view == FindView(isVisible: true, label: "1 of 3"))
    }

    @Test func labelRules() async {
        let f = FakeFind(); let s = makeFind(f)
        var seen: [FindView] = []
        s.onChange = { seen.append($0) }
        s.open()
        #expect(s.view == FindView(isVisible: true, label: ""))
        s.type("a"); await settle()
        await f.resume(.empty)
        #expect(s.view.label == "No results")
        s.type(""); await settle()
        #expect(s.view.label == "")
        #expect(f.cmds.last == .clear)
        #expect(seen.last == s.view)
    }

    @Test func failureKeepsStatusAndShowsError() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); await settle()
        await f.resume(FindStatus(count: 3, index: 1))
        s.next(); await settle()
        await f.fail()
        #expect(s.view.label == "Find failed")
        s.next(); await settle()
        await f.resume(FindStatus(count: 3, index: 2))
        #expect(s.view.label == "3 of 3")
    }

    @Test func latestWins() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); s.type("ab"); await settle()
        #expect(f.cmds == [.set("a"), .set("ab")])
        f.waiting.removeLast().resume(returning: FindStatus(count: 2, index: 0)); await settle()
        #expect(s.view.label == "1 of 2")
        await f.resume(FindStatus(count: 9, index: 4))
        #expect(s.view.label == "1 of 2")
    }

    @Test func closeBeforeResultDropsIt() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); await settle()
        s.close(); await settle()
        #expect(f.cmds == [.set("a"), .clear])
        await f.resume(FindStatus(count: 3, index: 0))
        #expect(s.view == .hidden)
        #expect(s.query == "")
    }

    @Test func stepCommands() async {
        let f = FakeFind(); f.immediate = .success(FindStatus(count: 3, index: 0)); let s = makeFind(f)
        s.next(); s.previous(); await settle()
        #expect(f.cmds.isEmpty)
        s.open(); s.next(); await settle()
        #expect(f.cmds.isEmpty)
        s.type("a"); s.next(); s.previous(); await settle()
        #expect(f.cmds == [.set("a"), .step(1), .step(-1)])
    }

    @Test func noContentSendsNothingUntilRender() async {
        let f = FakeFind(); let s = makeFind(f, ready: false)
        s.open(); s.type("a"); s.next(); await settle()
        #expect(f.cmds.isEmpty)
        s.renderDidComplete(); await settle()
        #expect(f.cmds == [.restore("a", 0)])
    }

    @Test func shellReloadKeepsIndexAndDropsOldResult() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); await settle()
        await f.resume(FindStatus(count: 5, index: 2))
        s.next(); await settle()
        #expect(f.cmds.count == 2)
        s.shellWillReload(); await settle()
        await f.resume(FindStatus(count: 5, index: 3))
        #expect(s.view.label == "3 of 5")
        s.next(); await settle()
        #expect(f.cmds.count == 2)
        s.renderDidComplete(); await settle()
        #expect(f.cmds.last == .restore("a", 2))
    }

    @Test func laterRenderSendsState() async {
        let f = FakeFind(); let s = makeFind(f)
        s.renderDidComplete(); await settle()
        #expect(f.cmds.isEmpty)
        s.open(); s.renderDidComplete(); await settle()
        #expect(f.cmds.isEmpty)
        s.type("a"); await settle()
        await f.resume(FindStatus(count: 3, index: 0))
        s.renderDidComplete(); await settle()
        #expect(f.cmds.last == .state)
        await f.fail()
        #expect(s.view.label == "Find failed")
        s.close(); s.renderDidComplete(); await settle()
        #expect(f.cmds.last == .clear)
    }

    @Test func errorThenSuccessClears() async {
        let f = FakeFind(); let s = makeFind(f)
        s.open(); s.type("a"); await settle()
        await f.fail()
        #expect(s.view.label == "Find failed")
        s.type("ab"); await settle()
        await f.resume(FindStatus(count: 1, index: 0))
        #expect(s.view.label == "1 of 1")
    }
}
