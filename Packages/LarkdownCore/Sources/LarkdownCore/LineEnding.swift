import Foundation

public enum LineEnding: String, Equatable, Sendable {
    case lf
    case crlf
    case mixed

    public var stringValue: String {
        switch self {
        case .lf, .mixed:
            "\n"
        case .crlf:
            "\r\n"
        }
    }

    public func normalizedSource(from source: String) -> String {
        switch self {
        case .lf, .mixed:
            source
        case .crlf:
            source.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
        }
    }
}

public enum LineEndingDetector {
    public static func detect(in source: String) -> LineEnding {
        let crlfCount = source.components(separatedBy: "\r\n").count - 1
        let bareLFCount = source.replacingOccurrences(of: "\r\n", with: "").components(separatedBy: "\n").count - 1

        if crlfCount > 0 && bareLFCount > 0 {
            return .mixed
        }

        if crlfCount > 0 {
            return .crlf
        }

        return .lf
    }
}
