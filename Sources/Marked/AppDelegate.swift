import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One window per document; the app quits when the last one closes (user request, S9).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
