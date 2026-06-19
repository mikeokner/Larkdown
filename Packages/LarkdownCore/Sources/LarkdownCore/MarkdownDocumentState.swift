import Foundation

public struct MarkdownDocumentState: Equatable, Sendable {
    public var source: String
    public var encoding: String.Encoding
    public var hasUTF8ByteOrderMark: Bool
    public var lineEnding: LineEnding
    public var frontMatter: FrontMatter?

    public init(source: String, encoding: String.Encoding = .utf8) {
        self.source = source
        self.encoding = encoding
        self.hasUTF8ByteOrderMark = false
        self.lineEnding = LineEndingDetector.detect(in: source)
        self.frontMatter = FrontMatterDetector.detect(in: source)
    }

    public init(data: Data) throws {
        let hasByteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        let sourceData = hasByteOrderMark ? data.dropFirst(3) : data[...]
        guard String(data: sourceData, encoding: .utf8) != nil else {
            throw MarkdownDocumentStateError.unsupportedEncoding
        }

        self.init(source: String(decoding: sourceData, as: UTF8.self), encoding: .utf8)
        self.hasUTF8ByteOrderMark = hasByteOrderMark
    }

    public func encodedData() -> Data {
        let normalized = lineEnding.normalizedSource(from: source)
        let data = normalized.data(using: encoding) ?? normalized.data(using: .utf8) ?? Data()
        return hasUTF8ByteOrderMark && encoding == .utf8 ? Data([0xEF, 0xBB, 0xBF]) + data : data
    }
}

public enum MarkdownDocumentStateError: Error, Equatable {
    case unsupportedEncoding
}
