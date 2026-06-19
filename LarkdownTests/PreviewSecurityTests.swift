import AppKit
import LarkdownCore
import Testing
import WebKit
@testable import Larkdown

@Suite(.serialized)
struct PreviewSecurityTests {
    // A 1x1 PNG.
    private let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    @MainActor
    @Test func previewRunsTrustedScriptAndBlocksDocumentCode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try tinyPNG.write(to: directory.appendingPathComponent("pixel image.png"))

        let source = """
        # Safe heading

        # Safe heading

        ```python
        print("hi")
        ```

        <img src="x" onerror="window.untrustedRan = true">
        <p onclick="window.untrustedRan = true">Click</p>
        <script>window.untrustedRan = true</script>

        ![local](pixel%20image.png)
        """
        let rendered = MarkdownRenderer().render(source: source)
        let controller = MarkdownPreviewViewController()
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        window.setContentSize(NSSize(width: 640, height: 480))
        let webView = try #require(controller.webView)

        controller.load(
            rendered: rendered,
            baseURL: PreviewResource.baseURL(forDocumentAt: directory.appendingPathComponent("README.md")),
            restoring: nil
        )

        // Our script ran: headings have slugs and code is highlighted.
        try await waitUntil(webView, "document.querySelector('pre code.hljs') !== null")
        #expect(try await evaluatePreviewScript(webView, "Array.from(document.querySelectorAll('h1')).map(h => h.id).join()") as? String == "safe-heading,safe-heading-1")
        // The document's own code did not.
        #expect(try await evaluatePreviewScript(webView, "window.untrustedRan === undefined") as? Bool == true)
        _ = try await evaluatePreviewScript(webView, "document.querySelector('p[onclick]').click(); true")
        #expect(try await evaluatePreviewScript(webView, "window.untrustedRan === undefined") as? Bool == true)
        // The scheme handler served the relative image.
        try await waitUntil(webView, "document.querySelector('img[alt=local]').naturalWidth > 0")
    }

    @MainActor
    private func waitUntil(_ webView: WKWebView, _ expression: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let value = try? await evaluatePreviewScript(webView, expression), value as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("WebKit did not reach expected state: \(expression)")
    }
}
