import SwiftUI
import MarkedCore

@main
struct MarkedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("style") private var stored = Style.default.rawValue

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { _ in
            ReaderView()
        }
        .commands {
            CommandGroup(after: .toolbar) {
                ForEach(Style.allCases, id: \.self) { s in
                    Toggle(s.title, isOn: Binding(
                        get: { Style(stored: stored) == s },
                        set: { if $0 { stored = s.rawValue } }))
                        .keyboardShortcut(KeyEquivalent(s.shortcut))
                }
            }
        }
    }
}
