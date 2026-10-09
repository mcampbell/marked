import SwiftUI
import MarkedCore

/// Sidebar state for one window. The coordinator sets `go` and feeds `update` after each render.
@MainActor
final class TOCController: ObservableObject {
    @Published private(set) var entries: [TOCEntry] = []
    /// Heading being read (S13 scroll-spy). May exceed `entries` until the next refresh lands.
    @Published private(set) var current: Int?
    var go: (Int) -> Void = { _ in }

    /// Keeps `current`: the spy computed it on the DOM these entries come from.
    func update(_ entries: [TOCEntry]) { self.entries = entries }
    func mark(_ i: Int?) { current = i }
}

struct TOCSidebar: View {
    @ObservedObject var toc: TOCController

    var body: some View {
        Group {
            if toc.entries.isEmpty {
                Text("No headings").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    // One Button per row, never List(selection:): marking a row must not scroll the page.
                    List {
                        ForEach(Array(toc.entries.enumerated()), id: \.offset) { i, e in
                            Button { toc.go(i) } label: {
                                Text(e.title).lineLimit(1).truncationMode(.tail)
                                    .fontWeight(i == toc.current ? .semibold : nil)
                                    .foregroundStyle(i == toc.current ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                    .padding(.leading, 12 * CGFloat(e.depth))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                    .onChange(of: toc.current) { reveal(proxy) }
                    // The mark can arrive before its row exists; retry once the new rows are laid out.
                    .onChange(of: toc.entries) { DispatchQueue.main.async { reveal(proxy) } }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
    }

    /// Scrolls the sidebar (never the page) just enough to show the current row.
    private func reveal(_ proxy: ScrollViewProxy) {
        if let c = toc.current, c < toc.entries.count { proxy.scrollTo(c) }
    }
}
