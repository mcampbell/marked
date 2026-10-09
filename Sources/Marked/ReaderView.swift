import SwiftUI

struct ReaderView: View {
    @Environment(\.documentConfiguration) private var config
    @State private var failure: String?
    @State private var banner: String?

    var body: some View {
        WebView(fileURL: config?.fileURL, failure: $failure, banner: $banner)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let banner {
                    Text(banner).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6).foregroundStyle(.white).background(.red)
                }
            }
            .navigationSubtitle(failure.map { "Render failed: \($0)" } ?? "")
    }
}
