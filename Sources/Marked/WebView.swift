import SwiftUI
@preconcurrency import WebKit
import MarkedCore

struct WebView: NSViewRepresentable {
    let fileURL: URL?
    let style: Style
    @Binding var failure: String?
    @Binding var styleFailure: String?
    @Binding var banner: String?
    let find: FindSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let c = context.coordinator
        c.setFailure = { [failure = $failure] in failure.wrappedValue = $0 }
        c.setStyleFailure = { [styleFailure = $styleFailure] in styleFailure.wrappedValue = $0 }
        c.setBanner = { [banner = $banner] in banner.wrappedValue = $0 }
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: DocURL.scheme)
        // Later slices append their scripts here.
        let scripts: [String] = [Self.resource("marked", "js"), Self.resource("scroll", "js", subdirectory: "js"),
                                 Self.resource("find", "js", subdirectory: "js")]
        for s in scripts {
            cfg.userContentController.addUserScript(
                WKUserScript(source: s, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = c
        c.start(web, fileURL: fileURL)
        c.apply(style)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.apply(style) }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

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
        var setStyleFailure: (String?) -> Void = { _ in }
        private var lastStyle: Style?
        var setBanner: (String?) -> Void = { _ in }
        private var watcher: FileWatcher?
        private var hasRendered = false
        private var shell: URL?

        func apply(_ style: Style) {
            // Remember the style only once the queue exists, so an early call cannot mark it as requested.
            guard let queue, style != lastStyle else { return }
            lastStyle = style
            queue.setStyle(WebView.resource(style.resource, "css", subdirectory: "styles"))
        }

        func stop() { watcher?.stop() }

        /// Follows symlinks: the handler serves the target, so the stamp must change when the target does.
        nonisolated static func mtime(_ path: String) -> Double? {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return (try? FileManager.default.attributesOfItem(atPath: resolved)[.modificationDate] as? Date)?.timeIntervalSince1970
        }

        func start(_ web: WKWebView, fileURL: URL?) {
            let shell = DocURL.shellURL(forDocument: fileURL ?? URL(fileURLWithPath: "/untitled.md"))
            self.shell = shell
            let queue = RenderQueue(render: { ImageStamp.apply(HTMLRenderer.render($0), shell: shell, mtime: Self.mtime) }) { [weak self, weak web] html, line in
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
            queue.changedLine = LineDiff.firstChangedLine
            self.queue = queue
            queue.onFailure = { [weak self] err in
                NSLog("Marked render failed: \(err)")
                self?.setFailure("\(err)")
            }
            queue.sendStyle = { [weak web] css in
                guard let web else { throw CocoaError(.userCancelled) }
                _ = try await web.callAsyncJavaScript("Marked.setStyle(css)", arguments: ["css": css], in: nil, contentWorld: .defaultClient)
            }
            queue.onStyleFailure = { [weak self] err in
                NSLog("Marked style failed: \(err)")
                self?.setStyleFailure("\(err)")
            }
            queue.onStyleApplied = { [weak self] in self?.setStyleFailure(nil) }
            web.load(URLRequest(url: shell))
            guard let fileURL else { setBanner("⚠ No file"); return }
            let w = FileWatcher(url: fileURL) { [weak self] ev in
                guard let self else { return }
                switch ev {
                case .text(let t):
                    hasRendered = true
                    queue.submit(t)
                case .error(let m):
                    setBanner(hasRendered ? "⚠ \(m) — showing the last good version" : "⚠ \(m)")
                case .cleared:
                    setBanner(nil)
                }
            }
            watcher = w
            w.start()
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
