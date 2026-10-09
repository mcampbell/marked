import SwiftUI
import MarkedCore

/// Thin SwiftUI wrapper over FindSession.
@MainActor
final class FindController: ObservableObject {
    @Published private(set) var view: FindView
    @Published var text = ""
    let session: FindSession

    init(session: FindSession) {
        self.session = session
        view = session.view
    }

    func show() {}
    func hide() {}
    func next() {}
    func previous() {}
}
