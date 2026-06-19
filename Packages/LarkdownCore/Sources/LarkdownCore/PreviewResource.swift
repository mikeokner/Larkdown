import Foundation

/// Maps local files to the `larkdown-file` URLs that the preview loads them from.
public enum PreviewResource {
    public static let scheme = "larkdown-file"

    /// Returns the preview base URL for a document, so relative paths resolve
    /// against the document's folder.
    public static func baseURL(forDocumentAt fileURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        var path = fileURL.deletingLastPathComponent().standardizedFileURL.path
        if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path
        return components.url!
    }

    /// Returns the file that a `larkdown-file` URL refers to, or `nil` for other schemes.
    public static func fileURL(for url: URL) -> URL? {
        guard url.scheme == scheme else {
            return nil
        }
        return URL(fileURLWithPath: url.path).standardizedFileURL
    }
}
