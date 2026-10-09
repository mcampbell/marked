import SwiftUI

struct ReaderView: View {
    @Environment(\.documentConfiguration) private var config
    @State private var failure: String?

    var body: some View {
        WebView(fileURL: config?.fileURL, failure: $failure)
            .navigationSubtitle(failure.map { "Render failed: \($0)" } ?? "")
    }
}
