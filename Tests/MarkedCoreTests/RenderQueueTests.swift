import Testing
@testable import MarkedCore

struct Boom: Error {}

@MainActor
final class FakeSend {
    var calls: [(html: String, line: Int?)] = []
    var waiting: [CheckedContinuation<RenderResult, Error>] = []
    var immediate: Result<RenderResult, Error>?

    func send(_ html: String, _ line: Int?) async throws -> RenderResult {
        calls.append((html, line))
        if let r = immediate { return try r.get() }
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
}

@MainActor
final class Counter {
    var seen: [String] = []
    var failures = 0
}

let ok = RenderResult(ok: true, errors: [])

@MainActor
func settle() async { for _ in 0..<30 { await Task.yield() } }

@MainActor
func make(_ f: FakeSend) -> RenderQueue {
    RenderQueue(render: { "<\($0)>" }, send: { h, l in try await f.send(h, l) })
}

@MainActor
@Suite struct RenderQueueTests {
    @Test func submitBeforeReadyDoesNotSend() async {
        let f = FakeSend(); let q = make(f)
        q.submit("a"); await settle()
        #expect(f.calls.isEmpty)
        q.markReady(); await settle()
        #expect(f.calls.count == 1)
        #expect(f.calls[0].html == "<a>")
    }

    @Test func markReadySendsLatest() async {
        let f = FakeSend(); let q = make(f)
        q.submit("a"); q.submit("b"); q.markReady(); await settle()
        #expect(f.calls.map(\.html) == ["<b>"])
    }

    @Test func threeSubmitsMidFlightCoalesce() async {
        let f = FakeSend(); let q = make(f)
        q.markReady(); q.submit("a"); await settle()
        q.submit("b"); q.submit("c"); q.submit("d"); await settle()
        #expect(f.calls.count == 1)
        f.waiting.removeFirst().resume(returning: ok); await settle()
        #expect(f.calls.map(\.html) == ["<a>", "<d>"])
        f.waiting.removeFirst().resume(returning: ok); await settle()
        #expect(f.calls.count == 2)
    }

    @Test func seamReceivesBaselineAndNext() async {
        let f = FakeSend(); f.immediate = .success(ok); let q = make(f)
        var pairs: [String] = []
        q.changedLine = { pairs.append("\($0)|\($1)"); return 7 }
        q.markReady(); q.submit("a"); await settle()
        #expect(f.calls[0].line == nil)
        #expect(pairs.isEmpty)
        q.submit("b"); await settle()
        #expect(f.calls[1].line == 7)
        #expect(pairs == ["a|b"])
    }

    @Test func notOkAdvancesBaseline() async {
        let f = FakeSend(); f.immediate = .success(RenderResult(ok: false, errors: ["x: y"]))
        let q = make(f)
        var seen: [String] = []
        q.changedLine = { b, _ in seen.append(b); return nil }
        q.markReady(); q.submit("a"); await settle()
        q.submit("b"); await settle()
        #expect(seen == ["a"])
    }

    @Test func throwKeepsBaselineAndReleasesSlot() async {
        let f = FakeSend(); let q = make(f)
        var seen: [String] = []
        var failures = 0
        q.changedLine = { b, _ in seen.append(b); return nil }
        q.onFailure = { _ in failures += 1 }
        q.markReady(); q.submit("a"); await settle()
        f.waiting.removeFirst().resume(returning: ok); await settle()   // baseline a
        q.submit("b"); await settle()
        f.waiting.removeFirst().resume(throwing: Boom()); await settle()
        #expect(failures == 1)
        q.submit("c"); await settle()
        #expect(f.calls.map(\.html) == ["<a>", "<b>", "<c>"])
        #expect(seen == ["a", "a"])
        #expect(failures == 1)
    }

    @Test func throwThenNewerPendingDispatches() async {
        let f = FakeSend(); let q = make(f)
        q.markReady(); q.submit("a"); await settle()
        q.submit("b"); await settle()
        f.waiting.removeFirst().resume(throwing: Boom()); await settle()
        #expect(f.calls.map(\.html) == ["<a>", "<b>"])
    }

    @Test func reloadThenReadyResendsLatestWithNil() async {
        let f = FakeSend(); f.immediate = .success(ok); let q = make(f)
        q.changedLine = { _, _ in 5 }
        q.markReady(); q.submit("a"); q.submit("b"); await settle()
        #expect(f.calls.count == 2 && f.calls[1].line == 5)
        q.shellWillReload(); await settle()
        #expect(f.calls.count == 2)
        q.markReady(); await settle()
        #expect(f.calls.count == 3)
        #expect(f.calls[2].html == "<b>" && f.calls[2].line == nil)
    }

    private func staleSetup() async -> (FakeSend, RenderQueue, CheckedContinuation<RenderResult, Error>, Counter) {
        let f = FakeSend(); let q = make(f); let c = Counter()
        q.changedLine = { b, _ in c.seen.append(b); return 1 }
        q.onFailure = { _ in c.failures += 1 }
        q.markReady(); q.submit("A"); await settle()
        let a = f.waiting.removeFirst()
        q.submit("B")
        q.shellWillReload(); q.markReady(); await settle()
        #expect(f.calls.map(\.html) == ["<A>", "<B>"])
        #expect(f.calls[1].line == nil)
        return (f, q, a, c)
    }

    @Test func staleSuccessDiscarded() async {
        let (f, q, a, c) = await staleSetup()
        a.resume(returning: ok); await settle()
        #expect(f.calls.count == 2)
        q.submit("C"); await settle()
        #expect(f.calls.count == 2)            // B slot still held
        #expect(c.failures == 0 && c.seen.isEmpty)
        f.waiting.removeFirst().resume(returning: ok); await settle()
        #expect(f.calls.map(\.html) == ["<A>", "<B>", "<C>"])
        #expect(c.seen == ["B"])               // baseline set by B, not A
    }

    @Test func staleThrowDiscarded() async {
        let (f, q, a, c) = await staleSetup()
        a.resume(throwing: Boom()); await settle()
        #expect(c.failures == 0)
        q.submit("C"); await settle()
        #expect(f.calls.count == 2)
        f.waiting.removeFirst().resume(returning: ok); await settle()
        #expect(f.calls.count == 3)
        #expect(c.seen == ["B"] && c.failures == 0)
    }
}
