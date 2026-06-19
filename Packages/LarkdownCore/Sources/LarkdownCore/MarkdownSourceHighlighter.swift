import Foundation

public enum MarkdownSourceTokenKind: Equatable, Sendable {
    case headingMarker
    case headingText
    case listMarker
    case blockQuoteMarker
    case codeFence
    case codeBlockContent
    case inlineCode
    case linkText
    case linkDestination
    case emphasisDelimiter
    case frontMatterDelimiter
    case frontMatterContent
    case thematicBreak
}

public struct MarkdownSourceToken: Equatable, Sendable {
    public var kind: MarkdownSourceTokenKind
    public var location: Int
    public var length: Int

    public init(kind: MarkdownSourceTokenKind, location: Int, length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }
}

public struct MarkdownSourceHighlighter: Sendable {
    public init() {}

    public func tokens(in source: String) -> [MarkdownSourceToken] {
        let nsSource = source as NSString
        var tokens: [MarkdownSourceToken] = []
        var isInFence = false
        var fenceMarker = ""
        var lineNumber = 0
        let frontMatter = FrontMatterDetector.detect(in: source)

        nsSource.enumerateSubstrings(
            in: NSRange(location: 0, length: nsSource.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            lineNumber += 1
            let line = nsSource.substring(with: lineRange)

            if let frontMatter {
                if lineNumber == 1 || lineNumber == frontMatter.endLine {
                    tokens.append(MarkdownSourceToken(kind: .frontMatterDelimiter, location: lineRange.location, length: lineRange.length))
                    return
                }

                if lineNumber < frontMatter.bodyStartLine {
                    tokens.append(MarkdownSourceToken(kind: .frontMatterContent, location: lineRange.location, length: lineRange.length))
                    return
                }
            }

            let leadingSpaces = countLeadingSpaces(in: line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isInFence {
                if isClosingFence(trimmed, marker: fenceMarker) {
                    tokens.append(MarkdownSourceToken(kind: .codeFence, location: lineRange.location, length: lineRange.length))
                    isInFence = false
                    fenceMarker = ""
                } else if lineRange.length > 0 {
                    tokens.append(MarkdownSourceToken(kind: .codeBlockContent, location: lineRange.location, length: lineRange.length))
                }
                return
            }

            if leadingSpaces <= 3, let marker = openingFenceMarker(in: trimmed) {
                tokens.append(MarkdownSourceToken(kind: .codeFence, location: lineRange.location, length: lineRange.length))
                isInFence = true
                fenceMarker = marker
                return
            }

            if leadingSpaces <= 3, isThematicBreak(trimmed) {
                tokens.append(MarkdownSourceToken(kind: .thematicBreak, location: lineRange.location, length: lineRange.length))
                return
            }

            highlightBlockSyntax(in: line, lineRange: lineRange, leadingSpaces: leadingSpaces, tokens: &tokens)
            highlightInlineSyntax(in: line, lineRange: lineRange, tokens: &tokens)
        }

        return tokens.sorted {
            if $0.location == $1.location {
                return $0.length > $1.length
            }
            return $0.location < $1.location
        }
    }
}

private func countLeadingSpaces(in line: String) -> Int {
    var count = 0
    for character in line {
        if character == " " {
            count += 1
        } else {
            break
        }
    }
    return count
}

private func openingFenceMarker(in trimmedLine: String) -> String? {
    if trimmedLine.hasPrefix("```") {
        return "```"
    }
    if trimmedLine.hasPrefix("~~~") {
        return "~~~"
    }
    return nil
}

private func isClosingFence(_ trimmedLine: String, marker: String) -> Bool {
    trimmedLine.hasPrefix(marker)
}

private func isThematicBreak(_ trimmedLine: String) -> Bool {
    let compact = trimmedLine.filter { !$0.isWhitespace }
    guard compact.count >= 3, let first = compact.first, first == "-" || first == "*" || first == "_" else {
        return false
    }
    return compact.allSatisfy { $0 == first }
}

private func highlightBlockSyntax(
    in line: String,
    lineRange: NSRange,
    leadingSpaces: Int,
    tokens: inout [MarkdownSourceToken]
) {
    guard leadingSpaces <= 3 else {
        return
    }

    let nsLine = line as NSString
    let markerStart = lineRange.location + leadingSpaces
    let trimmed = nsLine.substring(from: leadingSpaces)

    if let match = trimmed.range(of: #"^(#{1,6})(?:\s+|$)"#, options: .regularExpression) {
        let markerLength = trimmed.distance(from: match.lowerBound, to: match.upperBound)
        tokens.append(MarkdownSourceToken(kind: .headingMarker, location: markerStart, length: markerLength))
        let textLocation = markerStart + markerLength
        let textLength = max(0, lineRange.location + lineRange.length - textLocation)
        if textLength > 0 {
            tokens.append(MarkdownSourceToken(kind: .headingText, location: textLocation, length: textLength))
        }
        return
    }

    if trimmed.hasPrefix(">") {
        let markerLength = trimmed.hasPrefix("> ") ? 2 : 1
        tokens.append(MarkdownSourceToken(kind: .blockQuoteMarker, location: markerStart, length: markerLength))
    }

    if let match = trimmed.range(of: #"^([-+*]|\d+[.)])\s+(?:\[[ xX]\]\s+)?"#, options: .regularExpression) {
        let markerLength = trimmed.distance(from: match.lowerBound, to: match.upperBound)
        tokens.append(MarkdownSourceToken(kind: .listMarker, location: markerStart, length: markerLength))
    }
}

private func highlightInlineSyntax(in line: String, lineRange: NSRange, tokens: inout [MarkdownSourceToken]) {
    highlightInlineCode(in: line, lineRange: lineRange, tokens: &tokens)
    highlightLinks(in: line, lineRange: lineRange, tokens: &tokens)
    highlightEmphasisDelimiters(in: line, lineRange: lineRange, tokens: &tokens)
}

private func highlightInlineCode(in line: String, lineRange: NSRange, tokens: inout [MarkdownSourceToken]) {
    let nsLine = line as NSString
    var searchStart = 0
    while searchStart < nsLine.length {
        let opening = nsLine.range(of: "`", options: [], range: NSRange(location: searchStart, length: nsLine.length - searchStart))
        guard opening.location != NSNotFound else {
            return
        }

        let contentStart = opening.location + opening.length
        let closing = nsLine.range(of: "`", options: [], range: NSRange(location: contentStart, length: nsLine.length - contentStart))
        guard closing.location != NSNotFound else {
            return
        }

        let tokenLocation = lineRange.location + opening.location
        let tokenLength = closing.location + closing.length - opening.location
        tokens.append(MarkdownSourceToken(kind: .inlineCode, location: tokenLocation, length: tokenLength))
        searchStart = closing.location + closing.length
    }
}

private func highlightLinks(in line: String, lineRange: NSRange, tokens: inout [MarkdownSourceToken]) {
    guard let regex = try? NSRegularExpression(pattern: #"!?\[([^\]\n]+)\]\(([^)\n]+)\)"#) else {
        return
    }

    let nsLine = line as NSString
    let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
    for match in matches {
        guard match.numberOfRanges >= 3 else {
            continue
        }

        let textRange = match.range(at: 1)
        let destinationRange = match.range(at: 2)
        tokens.append(MarkdownSourceToken(kind: .linkText, location: lineRange.location + textRange.location, length: textRange.length))
        tokens.append(MarkdownSourceToken(kind: .linkDestination, location: lineRange.location + destinationRange.location, length: destinationRange.length))
    }
}

private func highlightEmphasisDelimiters(in line: String, lineRange: NSRange, tokens: inout [MarkdownSourceToken]) {
    let nsLine = line as NSString
    var index = 0
    while index < nsLine.length {
        let character = nsLine.character(at: index)
        if character == 42 || character == 95 {
            let nextIndex = index + 1
            let length = nextIndex < nsLine.length && nsLine.character(at: nextIndex) == character ? 2 : 1
            tokens.append(MarkdownSourceToken(kind: .emphasisDelimiter, location: lineRange.location + index, length: length))
            index += length
        } else {
            index += 1
        }
    }
}
