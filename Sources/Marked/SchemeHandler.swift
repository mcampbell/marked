import MarkedCore
import WebKit

final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let shell = Bundle.main.requiredResource("shell", "html")

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let req = urlSchemeTask.request
        var body: Data?
        var type = ""
        if req.httpMethod == "GET", let url = req.url {
            if let f = DocURL.appFile(for: url) {
                body = Bundle.main.requiredResource(f.name, f.ext, subdirectory: f.subdirectory)
                type = "text/css; charset=utf-8"
            } else if url.host == DocURL.docHost, url.lastPathComponent == DocURL.shellName {
                body = shell; type = "text/html; charset=utf-8"
            } else if url.host == DocURL.docHost, let path = DocURL.imageFile(for: url, probe: Self.probe) {
                body = try? Data(contentsOf: URL(fileURLWithPath: path))
                type = DocURL.contentType(forPath: path)
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

    static func probe(_ path: String) -> FileInfo? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved) else { return nil }
        return FileInfo(resolvedPath: resolved, isRegularFile: (attrs[.type] as? FileAttributeType) == .typeRegular)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

extension Bundle {
    /// A missing resource means a broken bundle, so fail loud instead of showing a blank page.
    func requiredResource(_ name: String, _ ext: String, subdirectory: String? = nil) -> Data {
        guard let url = url(forResource: name, withExtension: ext, subdirectory: subdirectory),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Marked.app is missing Resources/\(subdirectory.map { "\($0)/" } ?? "")\(name).\(ext)")
        }
        return data
    }
}
