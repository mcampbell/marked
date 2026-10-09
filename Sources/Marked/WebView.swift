import SwiftUI
@preconcurrency import WebKit
import MarkedCore

struct WebView: NSViewRepresentable {
    let fileURL: URL?
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let c = context.coordinator
        c.setFailure = { [failure = $failure] in failure.wrappedValue = $0 }
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: DocURL.scheme)
        // S0 entry only; later streams append.
        let scripts: [String] = [Self.resource("marked", "js")]
        for s in scripts {
            cfg.userContentController.addUserScript(
                WKUserScript(source: s, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = c
        c.start(web, fileURL: fileURL)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func resource(_ name: String, _ ext: String, subdirectory: String? = nil) -> String {
        String(decoding: Bundle.main.requiredResource(name, ext, subdirectory: subdirectory), as: UTF8.self)
    }

    struct BridgeError: Error, CustomStringConvertible {
        let raw: String
        var description: String { "Marked.render returned \(raw); expected {ok, errors}" }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var setFailure: (String?) -> Void = { _ in }
        private var queue: RenderQueue?
        private var shell: URL?

        func start(_ web: WKWebView, fileURL: URL?) {
            let shell = DocURL.shellURL(forDocument: fileURL ?? URL(fileURLWithPath: "/untitled.md"))
            self.shell = shell
            let queue = RenderQueue(render: HTMLRenderer.render) { [weak self, weak web] html, line in
                guard let web else { throw CocoaError(.userCancelled) }
                let args: [String: Any] = ["html": html, "changedLine": line.map { $0 as Any } ?? NSNull()]
                let raw = try await web.callAsyncJavaScript(
                    "return await Marked.render(html, changedLine)",
                    arguments: args, in: nil, contentWorld: .defaultClient)
                // Contract: see the Resources/marked.js header.
                guard let d = raw as? [String: Any], let ok = d["ok"] as? Bool,
                      let errors = d["errors"] as? [String] else { throw BridgeError(raw: raw.map { "\($0)" } ?? "nil") }
                self?.setFailure(nil)   // bridge works again; hook errors show in the page
                return RenderResult(ok: ok, errors: errors)
            }
            self.queue = queue
            queue.onFailure = { [weak self] err in
                NSLog("Marked render failed: \(err)")
                self?.setFailure("\(err)")
            }
            web.load(URLRequest(url: shell))
            if let fileURL {
                switch FileWatcher.read(fileURL) {
                case .success(let text): queue.submit(text)
                case .failure(let e): queue.submit("**Cannot display:** \(e)")
                }
            } else {
                queue.submit("**Cannot display:** no file")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            queue?.markReady()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            queue?.shellWillReload()
            if let shell { webView.load(URLRequest(url: shell)) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let shell else { return decisionHandler(.cancel) }
            var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
            bare?.fragment = nil
            decisionHandler(bare?.url == shell ? .allow : .cancel)
        }
    }
}
