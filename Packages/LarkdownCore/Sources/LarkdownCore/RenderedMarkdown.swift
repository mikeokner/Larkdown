import Foundation

public struct RenderedMarkdown: Equatable, Sendable {
    public var htmlBody: String
    public var previewDocument: String

    public init(htmlBody: String, previewDocument: String) {
        self.htmlBody = htmlBody
        self.previewDocument = previewDocument
    }
}
