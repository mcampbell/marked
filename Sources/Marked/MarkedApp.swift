import SwiftUI
import MarkedCore

/// Commands act on the key window's find bar. Resolved through AppKit at click time:
/// @FocusedValue / @FocusedObject stayed nil in this DocumentGroup (S3 live check).
struct FindCommands: Commands {
    private var find: FindController? { WebView.findController(in: NSApp.keyWindow) }

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") { find?.show() }.keyboardShortcut("f")
            Button("Find Next") { find?.next() }.keyboardShortcut("g")
            Button("Find Previous") { find?.previous() }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

@main
struct MarkedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("style") private var stored = Style.default.rawValue

    init() {
        // Aliases via the main menu, because a SwiftUI menu item takes one shortcut:
        // Ctrl-F -> Cmd-F (one Find path); Cmd-= -> Cmd-+ (bigger text with no Shift).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let alias: String? = switch (e.modifierFlags.intersection(.deviceIndependentFlagsMask), e.charactersIgnoringModifiers) {
            case (.control, "f"): "f"
            case (.command, "="): "+"
            default: nil
            }
            guard let alias,
                  let cmd = NSEvent.keyEvent(with: .keyDown, location: e.locationInWindow,
                                             modifierFlags: .command, timestamp: e.timestamp,
                                             windowNumber: e.windowNumber, context: nil,
                                             characters: alias, charactersIgnoringModifiers: alias,
                                             isARepeat: e.isARepeat, keyCode: e.keyCode),
                  NSApp.mainMenu?.performKeyEquivalent(with: cmd) == true else { return e }
            return nil
        }
    }

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { _ in
            ReaderView()
        }
        .commands {
            FindCommands()
            SidebarCommands()
            CommandGroup(replacing: .printItem) {
                Button("Print…") { WebView.webView(in: NSApp.keyWindow)?.printAsSheet() }.keyboardShortcut("p")
            }
            CommandGroup(after: .toolbar) {
                ForEach(Style.allCases, id: \.self) { s in
                    Toggle(s.title, isOn: Binding(
                        get: { Style(stored: stored) == s },
                        set: { if $0 { stored = s.rawValue } }))
                        .keyboardShortcut(KeyEquivalent(s.shortcut))
                }
                Divider()
                Button("Make Text Bigger") { WebView.changeTextSize(in: NSApp.keyWindow, step: 1) }.keyboardShortcut("+")
                Button("Make Text Smaller") { WebView.changeTextSize(in: NSApp.keyWindow, step: -1) }.keyboardShortcut("-")
                Button("Actual Size") { WebView.changeTextSize(in: NSApp.keyWindow, step: nil) }.keyboardShortcut("0")
            }
        }
    }
}
