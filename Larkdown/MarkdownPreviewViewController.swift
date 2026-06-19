import AppKit
import LarkdownCore
import WebKit

final class MarkdownPreviewViewController: NSViewController, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var revision = 0
    private var activeNavigation: WKNavigation?
    private var pendingScrollPosition: MarkdownEditorScrollPosition?
    private var isScrollUpdateScheduled = false
    private var hasLoadedPreviewDocument = false
    private var currentBaseURL: URL?
    private var lastRendered: RenderedMarkdown?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(PreviewResourceSchemeHandler(), forURLScheme: PreviewResource.scheme)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("Markdown preview")
        view = webView
    }

    func load(rendered: RenderedMarkdown, baseURL: URL?, restoring scrollPosition: MarkdownEditorScrollPosition?) {
        revision += 1
        lastRendered = rendered
        pendingScrollPosition = scrollPosition
        currentBaseURL = baseURL
        hasLoadedPreviewDocument = false
        activeNavigation = webView.loadHTMLString(rendered.previewDocument, baseURL: baseURL)
    }

    func update(rendered: RenderedMarkdown, baseURL: URL?, restoring scrollPosition: MarkdownEditorScrollPosition?) {
        revision += 1
        let updateRevision = revision
        lastRendered = rendered
        guard hasLoadedPreviewDocument, baseURL == currentBaseURL else {
            load(rendered: rendered, baseURL: baseURL, restoring: scrollPosition)
            return
        }

        pendingScrollPosition = scrollPosition
        guard let bodyLiteral = javaScriptStringLiteral(rendered.htmlBody) else {
            load(rendered: rendered, baseURL: baseURL, restoring: scrollPosition)
            return
        }

        // Without editor scroll state the preview keeps its own position.
        let script: String
        if let position = scrollPosition {
            let line = max(1, position.topVisibleLine)
            let fraction = min(max(position.scrollFraction, 0), 1)
            let isAtBottom = position.isAtBottom ? "true" : "false"
            script = "window.larkdownUpdatePreviewBody(\(bodyLiteral), \(line), \(fraction), \(isAtBottom));"
        } else {
            script = "window.larkdownUpdatePreviewBody(\(bodyLiteral), null, 0, false);"
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self, self.revision == updateRevision, error != nil else {
                return
            }
            self.load(rendered: rendered, baseURL: baseURL, restoring: scrollPosition)
        }
    }

    func scroll(to position: MarkdownEditorScrollPosition) {
        pendingScrollPosition = position
        guard hasLoadedPreviewDocument else {
            return
        }
        scheduleScrollPositionUpdate()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let lastRendered else { return }
        load(rendered: lastRendered, baseURL: currentBaseURL, restoring: pendingScrollPosition)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        hasLoadedPreviewDocument = true
        guard let pendingScrollPosition else {
            return
        }

        applyScrollPosition(pendingScrollPosition, animated: false)
    }

    private func scheduleScrollPositionUpdate() {
        guard !isScrollUpdateScheduled else {
            return
        }

        isScrollUpdateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            guard let self else {
                return
            }

            self.isScrollUpdateScheduled = false
            guard self.hasLoadedPreviewDocument,
                  let pendingScrollPosition = self.pendingScrollPosition else {
                return
            }

            self.applyScrollPosition(pendingScrollPosition, animated: true)
        }
    }

    private func applyScrollPosition(_ position: MarkdownEditorScrollPosition, animated: Bool) {
        guard hasLoadedPreviewDocument else {
            return
        }

        let line = max(1, position.topVisibleLine)
        let fraction = min(max(position.scrollFraction, 0), 1)
        let isAtBottom = position.isAtBottom ? "true" : "false"
        let shouldAnimate = animated ? "true" : "false"
        let script = "window.larkdownScrollToPosition(\(line), \(fraction), \(isAtBottom), \(shouldAnimate));"
        webView.evaluateJavaScript(script)
    }

    private func javaScriptStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return nil
        }

        return String(json.dropFirst().dropLast())
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.navigationType != .linkActivated {
            return navigationAction.targetFrame?.isMainFrame == true &&
                (url.scheme == "about" || url == currentBaseURL) ? .allow : .cancel
        }
        if isSameDocumentFragment(url) {
            return .allow
        }
        if let fileURL = PreviewResource.fileURL(for: url) {
            await openLocalFile(fileURL)
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    private func isSameDocumentFragment(_ url: URL) -> Bool {
        guard url.fragment != nil else { return false }
        let candidates = [currentBaseURL, webView.url].compactMap { $0 }
        return candidates.contains { withoutFragment($0) == withoutFragment(url) }
    }

    private func withoutFragment(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.fragment = nil
        return components.url
    }

    @MainActor
    private func openLocalFile(_ fileURL: URL) async {
        if isMarkdownFile(fileURL) {
            do {
                try await NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true)
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            // Launching arbitrary linked files is a hazard for downloaded
            // documents; reveal them in Finder instead.
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func isMarkdownFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown":
            return true
        default:
            return false
        }
    }
}
