import SwiftUI
import MarkedCore

/// Thin SwiftUI wrapper over FindSession.
@MainActor
final class FindController: ObservableObject {
    @Published private(set) var view: FindView
    @Published var text = "" {
        didSet {
            guard text != oldValue else { return }
            debounce?.cancel()
            debounce = Task { [weak self, text] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.session.type(text)
            }
        }
    }
    let session: FindSession
    private var debounce: Task<Void, Never>?

    init(session: FindSession) {
        self.session = session
        view = session.view
        session.onChange = { [weak self] in self?.view = $0 }
    }

    /// Bumped on every show() so the bar refocuses its field even when already open.
    @Published private(set) var focusRequest = 0
    func show() { session.open(); focusRequest += 1 }
    func hide() {
        text = ""
        debounce?.cancel() // drop the debounce the clear just scheduled
        debounce = nil
        session.close()
    }
    func next() { session.next() }
    func previous() { session.previous() }
}

