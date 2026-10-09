import SwiftUI

@main
struct MarkedApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { _ in
            ReaderView()
        }
    }
}
