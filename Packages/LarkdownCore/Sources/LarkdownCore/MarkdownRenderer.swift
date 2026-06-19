import Foundation
import cmark_gfm
import cmark_gfm_extensions

public struct MarkdownRenderer: Sendable {
    public init() {}

    public func render(source: String) -> RenderedMarkdown {
        let state = MarkdownDocumentState(source: source)
        let markdown = FrontMatterDetector.blankingFrontMatter(in: source, frontMatter: state.frontMatter)
        let htmlBody = Self.renderHTML(markdown)

        return RenderedMarkdown(
            htmlBody: htmlBody,
            previewDocument: PreviewHTMLDocument.make(body: htmlBody)
        )
    }

    private static func renderHTML(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        // Raw HTML passes through like it does on GitHub; the preview's
        // content security policy and the tagfilter extension contain it.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES
        let parser = cmark_parser_new(options)!
        defer { cmark_parser_free(parser) }

        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        var markdown = markdown
        markdown.withUTF8 { buffer in
            buffer.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress {
                    cmark_parser_feed(parser, base, chars.count)
                }
            }
        }

        let root = cmark_parser_finish(parser)!
        defer { cmark_node_free(root) }

        let html = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser))!
        defer { free(html) }
        return String(cString: html)
    }
}
