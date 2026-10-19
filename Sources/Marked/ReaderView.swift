import SwiftUI
import MarkedCore

struct ReaderView: View {
    @Environment(\.documentConfiguration) private var config
    @State private var failure: String?
    @State private var styleFailure: String?
    @State private var banner: String?
    @State private var textSize = TextSize.normal
    @AppStorage("style") private var stored = Style.default.rawValue
    @StateObject private var find = FindController(session: FindSession())
    @StateObject private var toc = TOCController()
    /// Global, so every window shows or hides the sidebar together (D40).
    @AppStorage("tocVisible") private var tocVisible = false

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { tocVisible ? .all : .detailOnly },
            set: { tocVisible = $0 != .detailOnly })) {
            TOCSidebar(toc: toc)
        } detail: {
            reader
        }
        .navigationSubtitle([TextSize.label(textSize), failure.map { "Render failed: \($0)" },
                             styleFailure.map { "Style failed: \($0)" }]
            .compactMap { $0 }.joined(separator: " · "))
    }

    private var reader: some View {
        WebView(fileURL: config?.fileURL, style: Style(stored: stored),
                failure: $failure, styleFailure: $styleFailure, banner: $banner, textSize: $textSize,
                find: find, toc: toc)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if find.view.isVisible { FindBar(find: find) }
                    if let banner {
                        Text(banner).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6).foregroundStyle(.white).background(.red)
                    }
                }
            }
    }
}
