import SwiftUI
import MarkedCore

struct FindBar: View {
    @ObservedObject var find: FindController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find", text: $find.text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { find.next() }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    find.previous()
                    return .handled
                }
                .onKeyPress(.escape) { find.hide(); return .handled }
            Text(find.view.label).foregroundStyle(.secondary)
            Button { find.previous() } label: { Image(systemName: "chevron.up") }
            Button { find.next() } label: { Image(systemName: "chevron.down") }
            Button { find.hide() } label: { Image(systemName: "xmark") }
        }
        .padding(6)
        .background(.bar)
        .onAppear { focused = true }
        .onChange(of: find.focusRequest) { focused = true }
    }
}
