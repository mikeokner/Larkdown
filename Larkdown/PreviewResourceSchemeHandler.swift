import Foundation
import LarkdownCore
import UniformTypeIdentifiers
import WebKit

/// Serves local files that a Markdown document references. The app process
/// reads them, so macOS applies its normal folder access prompts.
final class PreviewResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private var stoppedTasks: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = PreviewResource.fileURL(for: url) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<Data, Error> {
                let targetURL = fileURL.resolvingSymlinksInPath()
                guard try targetURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw URLError(.fileDoesNotExist)
                }
                return try Data(contentsOf: targetURL, options: .mappedIfSafe)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.stoppedTasks.remove(taskID) == nil else {
                    return
                }
                switch result {
                case .success(let data):
                    let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                case .failure(let error):
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
    }
}
