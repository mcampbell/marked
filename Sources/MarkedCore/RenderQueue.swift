@MainActor
public final class RenderQueue {
    public var changedLine: (String, String) -> Int? = { _, _ in nil }
    public var onFailure: (Error) -> Void = { _ in }
    /// S2 style seam (W2 stubs).
    public var sendStyle: (String) async throws -> Void = { _ in }
    public var onStyleApplied: () -> Void = {}
    public var onStyleFailure: (Error) -> Void = { _ in }

    private let render: (String) -> String
    private let send: (String, Int?) async throws -> RenderResult

    private var ready = false
    private var inFlight = false
    private var generation = 0
    private var pending: String?
    private var latest: String?
    private var lastRendered: String?
    private var currentStyle: String?
    private var pendingStyle: String?

    public init(
        render: @escaping (String) -> String,
        send: @escaping (String, Int?) async throws -> RenderResult
    ) {
        self.render = render
        self.send = send
    }

    public func submit(_ source: String) {
        latest = source
        pending = source
        pump()
    }

    public func setStyle(_ css: String) {
        currentStyle = css
        pendingStyle = css
        pump()
    }

    public func markReady() {
        ready = true
        pump()
    }

    public func shellWillReload() {
        generation += 1
        inFlight = false
        ready = false
        lastRendered = nil
        pending = latest
        pendingStyle = currentStyle
    }

    private func pump() {
        guard ready, !inFlight else { return }
        if let css = pendingStyle {
            inFlight = true
            let gen = generation
            Task { @MainActor in
                var failure: Error?
                do { try await sendStyle(css) } catch { failure = error }
                guard gen == generation else { return }
                if pendingStyle == css { pendingStyle = nil }
                inFlight = false
                if let failure { onStyleFailure(failure) } else { onStyleApplied() }
                pump()
            }
            return
        }
        guard let source = pending else { return }
        pending = nil
        inFlight = true
        let gen = generation
        let line = lastRendered.flatMap { changedLine($0, source) }
        let html = render(source)
        Task { @MainActor in
            do {
                _ = try await send(html, line)
                guard gen == generation else { return }
                lastRendered = source
                inFlight = false
            } catch {
                guard gen == generation else { return }
                inFlight = false
                onFailure(error)
            }
            pump()
        }
    }
}
