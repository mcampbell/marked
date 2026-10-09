import WebKit

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let shell = Bundle.main.url(forResource: "shell", withExtension: "html").flatMap { try? Data(contentsOf: $0) }
    private let css = Bundle.main.url(forResource: "base", withExtension: "css").flatMap { try? Data(contentsOf: $0) }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let req = urlSchemeTask.request
        var body: Data?
        var type = ""
        if req.httpMethod == "GET", let url = req.url {
            if url.host == "app", url.path == "/base.css" {
                body = css; type = "text/css; charset=utf-8"
            } else if url.host == "doc", url.lastPathComponent == "__marked__.html" {
                body = shell; type = "text/html; charset=utf-8"
            }
        }
        let url = req.url ?? URL(string: "marked://x/")!
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
