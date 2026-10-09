import Foundation
import cmark_gfm
import cmark_gfm_extensions

public enum HTMLRenderer {
    public static func render(_ source: String) -> String {
        guard let (fm, body) = FrontmatterSplit.split(source) else { return cmark(source) }
        return "<pre class=\"frontmatter\" data-sourcepos=\"1:1-\(fm.endLine):3\"><code>\(escape(fm.text))</code></pre>\n" + cmark(body)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func cmark(_ source: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        // NOBREAKS: a soft line break renders as a space, so wrapped text is identical to one line (and find matches across it).
        let options = CMARK_OPT_SOURCEPOS | CMARK_OPT_UNSAFE | CMARK_OPT_NOBREAKS
        let parser = cmark_parser_new(options)
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, source, source.utf8.count)
        let doc = cmark_parser_finish(parser)
        defer { cmark_node_free(doc) }
        guard let c = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(c) }
        return String(cString: c)
    }
}
