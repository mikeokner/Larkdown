import Foundation
import Testing
@testable import LarkdownCore

struct LarkdownCoreTests {
    @Test func detectsYamlFrontMatter() {
        let source = """
        ---
        title: Hello
        ---
        # Body
        """

        let frontMatter = FrontMatterDetector.detect(in: source)

        #expect(frontMatter?.kind == .yaml)
        #expect(frontMatter?.endLine == 3)
        #expect(frontMatter?.bodyStartLine == 4)
    }

    @Test func detectsYamlFrontMatterWithCRLFLineEndings() {
        let source = "---\r\ntitle: Hello\r\n---\r\n# Body\r\n"

        let frontMatter = FrontMatterDetector.detect(in: source)

        #expect(frontMatter?.kind == .yaml)
        #expect(frontMatter?.endLine == 3)
        #expect(frontMatter?.bodyStartLine == 4)
    }

    @Test func preservesConsistentCRLFWhenEncoding() throws {
        let state = try MarkdownDocumentState(data: Data("one\r\ntwo\r\n".utf8))

        #expect(state.lineEnding == LineEnding.crlf)
        #expect(String(data: state.encodedData(), encoding: .utf8) == "one\r\ntwo\r\n")
    }

    @Test func preservesLFWhenEncoding() throws {
        let source = "# Title\n\nA paragraph.\n"
        let state = try MarkdownDocumentState(data: Data(source.utf8))

        #expect(state.lineEnding == LineEnding.lf)
        #expect(String(data: state.encodedData(), encoding: .utf8) == source)
    }

    @Test func preservesMixedLineEndingsWithoutNormalizing() throws {
        let source = "one\r\ntwo\nthree\r\n"
        let state = try MarkdownDocumentState(data: Data(source.utf8))

        #expect(state.lineEnding == LineEnding.mixed)
        #expect(String(data: state.encodedData(), encoding: .utf8) == source)
    }

    @Test func preservesFrontMatterBytesAcrossRoundTrip() throws {
        let source = """
        ---
        title: Exact
        draft: true
        ---

        # Body
        """
        let state = try MarkdownDocumentState(data: Data(source.utf8))

        #expect(state.frontMatter?.kind == .yaml)
        #expect(String(data: state.encodedData(), encoding: .utf8) == source)
    }

    @Test func preservesUTF8ByteOrderMarkWithoutIncludingItInSource() throws {
        for source in ["", "# Title\r\n", "\u{FEFF}Content\n"] {
            let bytes = Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8)
            let state = try MarkdownDocumentState(data: bytes)
            #expect(state.source == source)
            #expect(state.hasUTF8ByteOrderMark)
            #expect(state.encodedData() == bytes)
        }
        #expect(!MarkdownDocumentState(source: "# New").hasUTF8ByteOrderMark)
    }

    @Test func supportsEmptyMarkdownFiles() throws {
        let state = try MarkdownDocumentState(data: Data())

        #expect(state.source == "")
        #expect(state.lineEnding == LineEnding.lf)
        #expect(state.encodedData().isEmpty)
    }

    @Test func rejectsUnsupportedEncodingsWithoutDataLoss() {
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])

        #expect(throws: MarkdownDocumentStateError.unsupportedEncoding) {
            _ = try MarkdownDocumentState(data: invalidUTF8)
        }
    }

    @Test func hidesFrontMatterAndKeepsEditorLineNumbers() {
        let cases: [(source: String, headingLine: Int)] = [
            ("---\ntitle: Hello\n---\n# Body", 4),
            ("+++\ntitle = \"Hello\"\n+++\r\n# Body", 4),
            ("---\r\ntitle: Hello\r\n---\r\n\r\n# Body", 5)
        ]

        for (source, headingLine) in cases {
            let html = MarkdownRenderer().render(source: source).htmlBody

            #expect(!html.contains("title"))
            #expect(html.contains("<h1 data-sourcepos=\"\(headingLine):1-"))
        }
    }

    @Test func rendersGitHubFlavoredMarkdown() {
        let source = """
        - [x] Done
        - [ ] Todo

        | A | B |
        | --- | --- |
        | 1 | 2 |

        ~~gone~~ and https://example.com/auto

        Note[^1]

        [^1]: The footnote.

        ```swift
        let value = 1
        ```
        """

        let html = MarkdownRenderer().render(source: source).htmlBody

        #expect(html.contains(#"<input type="checkbox" checked="""#))
        #expect(html.contains("<table"))
        #expect(html.contains("<del>gone</del>"))
        #expect(html.contains(#"<a href="https://example.com/auto">"#))
        #expect(html.contains(#"<section class="footnotes""#))
        #expect(html.contains("language-swift"))
    }

    @Test func passesRawHTMLThrough() {
        let source = """
        <!-- Don't show this -->
        <p align="center"><img src="logo.png" width="128"></p>
        """

        let html = MarkdownRenderer().render(source: source).htmlBody

        #expect(html.contains(#"<p align="center"><img src="logo.png" width="128"></p>"#))
        #expect(html.contains("<!-- Don't show this -->"))
    }

    @Test func neutralizesScriptTags() {
        let html = MarkdownRenderer().render(source: "Hello <script>alert(1)</script>\n\n<script>\nalert(2)\n</script>").htmlBody

        #expect(!html.contains("<script"))
        #expect(html.contains("&lt;script>"))
    }

    @Test func rendersStableSampleFixture() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "sample", withExtension: "md"))
        let source = try String(contentsOf: fixtureURL, encoding: .utf8)

        let state = MarkdownDocumentState(source: source)
        let rendered = MarkdownRenderer().render(source: source)

        #expect(state.frontMatter?.kind == .yaml)
        #expect(!rendered.htmlBody.contains("title: Larkdown Alpha Fixture"))
        #expect(rendered.htmlBody.contains("<h1"))
        #expect(rendered.htmlBody.contains("<table"))
        #expect(rendered.htmlBody.contains("language-python"))
        #expect(rendered.htmlBody.contains(#"src="images/diagram.png""#))
    }

    @Test func codeBlocksCarryTheirLanguageForHighlighting() {
        let source = """
        ```python
        def myfunc(bar, baz):
            \"\"\"
            do something
            \"\"\"
            # Do it
            xyz = foo.abc('bar')
        ```
        """

        let rendered = MarkdownRenderer().render(source: source)

        #expect(rendered.htmlBody.contains(#"<code class="language-python">"#))
    }

    @Test func identifiesMarkdownSourceHighlightTokens() {
        let source = """
        ---
        title: Demo
        ---
        # Heading

        - [x] Done with `code`
        > Quote with [link](https://example.com)

        ```python
        print("hello")
        ```
        """

        let tokens = MarkdownSourceHighlighter().tokens(in: source)
        let kinds = Set(tokens.map(\.kind))

        #expect(kinds.contains(.frontMatterDelimiter))
        #expect(kinds.contains(.frontMatterContent))
        #expect(kinds.contains(.headingMarker))
        #expect(kinds.contains(.headingText))
        #expect(kinds.contains(.listMarker))
        #expect(kinds.contains(.inlineCode))
        #expect(kinds.contains(.blockQuoteMarker))
        #expect(kinds.contains(.linkText))
        #expect(kinds.contains(.linkDestination))
        #expect(kinds.contains(.codeFence))
        #expect(kinds.contains(.codeBlockContent))
    }

    @Test func previewDocumentUsesNonceContentSecurityPolicy() throws {
        let document = MarkdownRenderer().render(source: "# Title").previewDocument

        let policy = try #require(document.components(separatedBy: #"Content-Security-Policy" content=""#).last?
            .components(separatedBy: "\"").first)
        #expect(policy.contains("default-src 'none'"))
        #expect(policy.contains("script-src 'nonce-"))
        #expect(policy.contains("img-src larkdown-file: data: https: http:"))
        #expect(!policy.contains("unsafe-inline"))
    }

    @Test func previewResourceRoundTripsUnusualPaths() throws {
        let documentURL = URL(fileURLWithPath: "/Users/test/My Docs/日本語 #1/README.md")

        let baseURL = PreviewResource.baseURL(forDocumentAt: documentURL)
        let imageURL = try #require(URL(string: "../img/café 1.png".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!, relativeTo: baseURL))

        #expect(baseURL.scheme == PreviewResource.scheme)
        #expect(baseURL.absoluteString.hasSuffix("/"))
        #expect(PreviewResource.fileURL(for: baseURL)?.path == "/Users/test/My Docs/日本語 #1")
        #expect(PreviewResource.fileURL(for: imageURL.absoluteURL)?.path == "/Users/test/My Docs/img/café 1.png")
        #expect(PreviewResource.fileURL(for: URL(string: "https://example.com/a.png")!) == nil)
    }
}
