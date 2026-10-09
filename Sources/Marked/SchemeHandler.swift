import MarkedCore
import WebKit

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let shell = Bundle.main.requiredResource("shell", "html")
    private let css = Bundle.main.requiredResource("base", "css")

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let req = urlSchemeTask.request
        var body: Data?
        var type = ""
        if req.httpMethod == "GET", let url = req.url {
            if url.host == DocURL.appHost, url.path == "/base.css" {
                body = css; type = "text/css; charset=utf-8"
            } else if url.host == DocURL.docHost, url.lastPathComponent == DocURL.shellName {
                body = shell; type = "text/html; charset=utf-8"
            }
        }
        let url = req.url ?? DocURL.appURL("")
        guard let body else {
            urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!)
            urlSchemeTask.didFinish()
            return
        }
        urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": type, "Content-Length": "\(body.count)"])!)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

extension Bundle {
    /// A missing resource means a broken bundle, so fail loud instead of showing a blank page.
    func requiredResource(_ name: String, _ ext: String) -> Data {
        guard let url = url(forResource: name, withExtension: ext), let data = try? Data(contentsOf: url) else {
            preconditionFailure("Marked.app is missing Resources/\(name).\(ext)")
        }
        return data
    }
}
