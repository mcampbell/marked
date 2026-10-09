import Testing
@testable import MarkedCore

private final class Reader {
    var calls = 0
    var results: [Result<String, ReadFailure>]
    init(_ r: [Result<String, ReadFailure>]) { results = r }
    func read() -> Result<String, ReadFailure> {
        calls += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

private func s(_ m: Double) -> Probe { .present(Stamp(mtime: m, size: 1)) }
private func ok(_ t: String) -> Result<String, ReadFailure> { .success(t) }
private func bad(_ m: String) -> Result<String, ReadFailure> { .failure(ReadFailure(message: m)) }

@Suite struct WatchStateTests {
    @Test func firstPresentReads() {
        var w = WatchState(); let r = Reader([ok("a")])
        #expect(w.step(s(1), read: r.read) == [.text("a")])
    }

    @Test func sameStampNoRead() {
        var w = WatchState(); let r = Reader([ok("a")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(1), read: r.read) == [])
        #expect(r.calls == 1)
    }

    @Test func newStampSameText() {
        var w = WatchState(); let r = Reader([ok("a")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(2), read: r.read) == [])
        #expect(r.calls == 2)
    }

    @Test func newStampNewText() {
        var w = WatchState(); let r = Reader([ok("a"), ok("b")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(2), read: r.read) == [.text("b")])
    }

    @Test func failureEmitsError() {
        var w = WatchState(); let r = Reader([bad("x")])
        #expect(w.step(s(1), read: r.read) == [.error("x")])
    }

    @Test func sameFailureNewStampDeduped() {
        var w = WatchState(); let r = Reader([bad("x")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(2), read: r.read) == [])
    }

    @Test func failureRetriedOnSameStamp() {
        var w = WatchState(); let r = Reader([bad("x"), bad("x"), ok("a")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(1), read: r.read) == [])
        #expect(r.calls == 2)
        #expect(w.step(s(1), read: r.read) == [.cleared, .text("a")])
    }

    @Test func noReadAfterSuccessSameStamp() {
        var w = WatchState(); let r = Reader([bad("x"), ok("a")])
        _ = w.step(s(1), read: r.read)
        _ = w.step(s(1), read: r.read)
        _ = w.step(s(1), read: r.read)
        #expect(r.calls == 2)
    }

    @Test func recoverySameTextOnlyCleared() {
        var w = WatchState(); let r = Reader([ok("a"), bad("x"), ok("a")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(s(2), read: r.read) == [.error("x")])
        #expect(w.step(s(3), read: r.read) == [.cleared])
    }

    @Test func oneMissingSilent() {
        var w = WatchState(); let r = Reader([ok("a")])
        #expect(w.step(.missing, read: r.read) == [])
        #expect(r.calls == 0)
    }

    @Test func twoMissingErrorOnce() {
        var w = WatchState(); let r = Reader([ok("a")])
        _ = w.step(.missing, read: r.read)
        #expect(w.step(.missing, read: r.read) == [.error("File not found")])
        #expect(w.step(.missing, read: r.read) == [])
    }

    @Test func missingThenPresentAtomicSave() {
        var w = WatchState(); let r = Reader([ok("a"), ok("b")])
        _ = w.step(s(1), read: r.read)
        #expect(w.step(.missing, read: r.read) == [])
        #expect(w.step(s(1), read: r.read) == [.text("b")])
        #expect(r.calls == 2)
    }

    @Test func errorThenPresentClears() {
        var w = WatchState(); let r = Reader([ok("a")])
        _ = w.step(s(1), read: r.read)
        _ = w.step(.missing, read: r.read)
        _ = w.step(.missing, read: r.read)
        #expect(w.step(s(1), read: r.read) == [.cleared])
    }
}
