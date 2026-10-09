import SwiftUI
import MarkedCore

struct ReaderView: View {
    @Environment(\.documentConfiguration) private var config
    @State private var failure: String?
    @State private var styleFailure: String?
    @State private var banner: String?
    @AppStorage("style") private var stored = Style.default.rawValue
    @StateObject private var find = FindController(session: FindSession())

    var body: some View {
        WebView(fileURL: config?.fileURL, style: Style(stored: stored),
                failure: $failure, styleFailure: $styleFailure, banner: $banner, find: find.session)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if find.view.isVisible { FindBar(find: find) }
                    if let banner {
                        Text(banner).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6).foregroundStyle(.white).background(.red)
                    }
                }
            }
            .focusedSceneValue(\.findController, find)
            .navigationSubtitle([failure.map { "Render failed: \($0)" }, styleFailure.map { "Style failed: \($0)" }]
                .compactMap { $0 }.joined(separator: " · "))
    }
}
