import SwiftUI
@preconcurrency import WebKit
import MarkedCore

struct WebView: NSViewRepresentable {
    let fileURL: URL?
    let style: Style
    @Binding var failure: String?
    @Binding var styleFailure: String?
    @Binding var banner: String?
    let find: FindController

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
                                 Self.resource("find", "js", subdirectory: "js"),
                                 Self.resource("mermaid.min", "js", subdirectory: "vendor"),
                                 Self.resource("mermaid-hook", "js", subdirectory: "js"),
                                 Self.resource("anchors", "js", subdirectory: "js")]
        for s in scripts {
            cfg.userContentController.addUserScript(
                WKUserScript(source: s, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = c
        c.findController = find
        c.start(web, fileURL: fileURL, find: find.session)
        c.apply(style)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.apply(style) }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// The find controller of the document shown in `window`, if any.
    @MainActor static func findController(in window: NSWindow?) -> FindController? {
        func web(in v: NSView) -> WKWebView? {
            if let w = v as? WKWebView { return w }
            return v.subviews.lazy.compactMap(web).first
        }
        return window?.contentView.flatMap(web).flatMap { ($0.navigationDelegate as? Coordinator)?.findController }
    }

    static func resource(_ name: String, _ ext: String, subdirectory: String? = nil) -> String {
        String(decoding: Bundle.main.requiredResource(name, ext, subdirectory: subdirectory), as: UTF8.self)
    }

    struct BridgeError: Error, CustomStringConvertible {
        let raw: String
        var description: String { "Marked.render returned \(raw); expected {ok, errors}" }
    }

    struct FindBridgeError: Error, CustomStringConvertible {
        let call: String
        let raw: String
        var description: String { "Marked.find.\(call) returned \(raw); expected {count, index}" }
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
        weak var findController: FindController?
        /// Runs the side effect of a link click. A seam so a live check can record instead of open.
        var performLink: (LinkAction) -> Void = { _ in }

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

        func start(_ web: WKWebView, fileURL: URL?, find: FindSession) {
            find.send = { [weak web] cmd in
                guard let web else { throw CocoaError(.userCancelled) }
                let (js, args, name): (String, [String: Any], String) = switch cmd {
                case .set(let q): ("return Marked.find.set(q)", ["q": q], "set")
                case .step(let d): ("return Marked.find.step(d)", ["d": d], "step")
                case .restore(let q, let i): ("return Marked.find.restore(q, i)", ["q": q, "i": i], "restore")
                case .clear: ("return Marked.find.clear()", [:], "clear")
                case .state: ("return Marked.find.state()", [:], "state")
                }
                do {
                    let raw = try await web.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .defaultClient)
                    guard let d = raw as? [String: Any], let count = d["count"] as? Int, let index = d["index"] as? Int
                    else { throw FindBridgeError(call: name, raw: raw.map { "\($0)" } ?? "nil") }
                    return FindStatus(count: count, index: index)
                } catch {
                    NSLog("Marked find failed: \(error)")
                    throw error
                }
            }
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
            queue.onRendered = { [weak find] in find?.renderDidComplete() }
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
            findController?.session.shellWillReload()
            if let shell { webView.load(URLRequest(url: shell)) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let shell else { return decisionHandler(.cancel) }
            let a = LinkPolicy.decide(url, shell: shell, linkActivated: action.navigationType == .linkActivated)
            if a != .allow && a != .cancel { performLink(a) }
            decisionHandler(a == .allow ? .allow : .cancel)
        }
    }
}
