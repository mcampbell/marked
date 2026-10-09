import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
