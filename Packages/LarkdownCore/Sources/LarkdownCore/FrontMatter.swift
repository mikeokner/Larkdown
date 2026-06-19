import Foundation

public struct FrontMatter: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case yaml
        case toml
    }

    public var kind: Kind
    public var rawText: String
    public var startLine: Int
    public var endLine: Int
    public var bodyStartLine: Int

    public init(kind: Kind, rawText: String, startLine: Int, endLine: Int, bodyStartLine: Int) {
        self.kind = kind
        self.rawText = rawText
        self.startLine = startLine
        self.endLine = endLine
        self.bodyStartLine = bodyStartLine
    }
}

public enum FrontMatterDetector {
    public static func detect(in source: String) -> FrontMatter? {
        let lines = logicalLines(in: source)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let kind: FrontMatter.Kind
        let marker: String
        switch first {
        case "---":
            kind = .yaml
            marker = "---"
        case "+++":
            kind = .toml
            marker = "+++"
        default:
            return nil
        }

        guard lines.count > 1 else {
            return nil
        }

        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                let raw = lines[0...index].joined(separator: "\n")
                return FrontMatter(
                    kind: kind,
                    rawText: raw,
                    startLine: 1,
                    endLine: index + 1,
                    bodyStartLine: index + 2
                )
            }
        }

        return nil
    }

    /// Returns the source with front matter lines emptied so that the
    /// remaining lines keep their original line numbers.
    public static func blankingFrontMatter(in source: String, frontMatter: FrontMatter?) -> String {
        guard let frontMatter else {
            return source
        }

        var lines = logicalLines(in: source)
        for index in 0..<min(frontMatter.endLine, lines.count) {
            lines[index] = ""
        }
        return lines.joined(separator: "\n")
    }

    private static func logicalLines(in source: String) -> [String] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
