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
    let toc: TOCController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let c = context.coordinator
        c.setFailure = { [failure = $failure] in failure.wrappedValue = $0 }
        c.setStyleFailure = { [styleFailure = $styleFailure] in styleFailure.wrappedValue = $0 }
        c.setBanner = { [banner = $banner] in banner.wrappedValue = $0 }
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        cfg.preferences.shouldPrintBackgrounds = true
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: DocURL.scheme)
        // Later slices append their scripts here.
        let scripts: [String] = [Self.resource("marked", "js"), Self.resource("scroll", "js", subdirectory: "js"),
                                 Self.resource("find", "js", subdirectory: "js"),
                                 Self.resource("mermaid.min", "js", subdirectory: "vendor"),
                                 Self.resource("mermaid-hook", "js", subdirectory: "js"),
                                 Self.resource("anchors", "js", subdirectory: "js"),
                                 Self.resource("highlight", "js", subdirectory: "js"),
                                 Self.resource("highlight.min", "js", subdirectory: "vendor"),
                                 Self.resource("syntax", "js", subdirectory: "js"),
                                 Self.resource("toc", "js", subdirectory: "js")]
        for s in scripts {
            cfg.userContentController.addUserScript(
                WKUserScript(source: s, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        cfg.userContentController.add(TOCMessages(c), contentWorld: .defaultClient, name: "toc")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = c
        c.findController = find
        c.tocController = toc
        c.start(web, fileURL: fileURL, find: find.session)
        c.apply(style)
        // Container, not the web view itself: SwiftUI keeps a closed document window's views alive
        // (dismantleNSView never runs), so on close the coordinator detaches the web view to free it.
        let box = NSView()
        web.frame = box.bounds
        web.autoresizingMask = [.width, .height]
        box.addSubview(web)
        c.freeOnClose(web)
        return box
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.apply(style) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// The web view of the document shown in `window`, if any.
    @MainActor static func webView(in window: NSWindow?) -> WKWebView? {
        func web(in v: NSView) -> WKWebView? {
            if let w = v as? WKWebView { return w }
            return v.subviews.lazy.compactMap(web).first
        }
        return window?.contentView.flatMap(web)
    }

    /// The find controller of the document shown in `window`, if any.
    @MainActor static func findController(in window: NSWindow?) -> FindController? {
        (webView(in: window)?.navigationDelegate as? Coordinator)?.findController
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
        weak var tocController: TOCController?
        /// Bumped per TOC refresh; a reply from an older refresh is dropped.
        private var tocGeneration = 0
        /// Runs the side effect of a link click. A seam so a live check can record instead of open.
        var performLink: (LinkAction) -> Void = { action in
            switch action {
            case .allow, .cancel:
                return
            case .openExternal(let u):
                NSLog("Marked link: openExternal %@", u.absoluteString)
                NSWorkspace.shared.open(u)
            case .openDocument(let u):
                NSLog("Marked link: openDocument %@", u.absoluteString)
                NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, error in
                    if let error { DispatchQueue.main.async { _ = NSApp.presentError(error) } }
                }
            case .reveal(let u):
                NSLog("Marked link: reveal %@", u.absoluteString)
                if FileManager.default.fileExists(atPath: u.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([u])
                } else {
                    _ = NSApp.presentError(CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: u.path]))
                }
            }
        }

        func apply(_ style: Style) {
            // Remember the style only once the queue exists, so an early call cannot mark it as requested.
            guard let queue, style != lastStyle else { return }
            lastStyle = style
            queue.setStyle(WebView.resource(style.resource, "css", subdirectory: "styles"))
        }

        func stop() {
            watcher?.stop()
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = nil
        }

        private var closeObserver: NSObjectProtocol?

        /// When this web view's window closes: stop polling and drop the web view, which then deallocates
        /// and closes its page. The closed window itself stays alive (SwiftUI DocumentGroup, macOS 26).
        func freeOnClose(_ web: WKWebView) {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self, weak web] note in
                let closing = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let web, let window = web.window, closing == ObjectIdentifier(window) else { return }
                    self?.stop()
                    web.removeFromSuperview()
                }
            }
        }

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
            tocController?.go = { [weak web] i in
                Task { _ = try? await web?.callAsyncJavaScript(
                    "return Marked.toc.go(i)", arguments: ["i": i], in: nil, contentWorld: .defaultClient) }
            }
            queue.onRendered = { [weak find, weak self, weak web] in
                find?.renderDidComplete()
                if let web { self?.refreshTOC(web) }
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

        /// Re-reads the headings after a render. Runs from `onRendered`, which also fires after a shell reload.
        func refreshTOC(_ web: WKWebView) {
            tocGeneration += 1
            let gen = tocGeneration
            Task { [weak self, weak web] in
                guard let web else { return }
                let entries: [TOCEntry]
                do {
                    let raw = try await web.callAsyncJavaScript(
                        "return Marked.toc.headings()", arguments: [:], in: nil, contentWorld: .defaultClient)
                    entries = try TOC.parse(raw)
                } catch {
                    NSLog("Marked toc failed: \(error)")
                    entries = []
                }
                guard let self, gen == tocGeneration else { return }
                tocController?.update(entries)
            }
        }

        /// S13 scroll-spy post from `js/toc.js`.
        func tocMessage(_ body: Any) {
            do { tocController?.mark(try TOC.current(body)) } catch { NSLog("Marked toc spy: \(error)") }
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
            // Answer WebKit first: an effect can show an app-modal alert (missing file).
            decisionHandler(a == .allow ? .allow : .cancel)
            if a != .allow && a != .cancel { performLink(a) }
        }
    }
}

extension WKWebView {
    /// One place for print settings, so the Print command and a live check print the same way.
    func makePrintOperation() -> NSPrintOperation {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false
        info.isVerticallyCentered = false
        return printOperation(with: info)
    }

    /// Print panel as a sheet on this view's window; no window → no-op.
    func printAsSheet() {
        guard let window else { return }
        makePrintOperation().runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

/// Receives `toc` posts in the `.defaultClient` world. The content controller holds this strongly;
/// it holds the coordinator weakly, so the handler never keeps the coordinator alive.
final class TOCMessages: NSObject, WKScriptMessageHandler {
    private weak var coordinator: WebView.Coordinator?

    init(_ coordinator: WebView.Coordinator) { self.coordinator = coordinator }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        coordinator?.tocMessage(message.body)
    }
}
