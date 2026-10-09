import SwiftUI
import MarkedCore

/// Sidebar state for one window. The coordinator sets `go` and feeds `update` after each render.
@MainActor
final class TOCController: ObservableObject {
    @Published private(set) var entries: [TOCEntry] = []
    var go: (Int) -> Void = { _ in }

    func update(_ entries: [TOCEntry]) { self.entries = entries }
}

struct TOCSidebar: View {
    @ObservedObject var toc: TOCController

    var body: some View {
        Group {
            if toc.entries.isEmpty {
                Text("No headings").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // One Button per row, never List(selection:): marking a row (S13) must not scroll the page.
                List {
                    ForEach(Array(toc.entries.enumerated()), id: \.offset) { i, e in
                        Button { toc.go(i) } label: {
                            Text(e.title).lineLimit(1).truncationMode(.tail)
                                .padding(.leading, 12 * CGFloat(e.depth))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
    }
}
