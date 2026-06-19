import Foundation
import WebKit

// A nonresponsive WebKit process must fail a test instead of hanging the suite.
@MainActor
func evaluatePreviewScript(_ webView: WKWebView, _ script: String) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
        var completed = false
        webView.evaluateJavaScript(script) { result, error in
            guard !completed else { return }
            completed = true
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: result) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !completed else { return }
            completed = true
            continuation.resume(throwing: NSError(domain: "WebKitTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebKit script evaluation timed out"]))
        }
    }
}
