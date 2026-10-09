import WebKit

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {}
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
