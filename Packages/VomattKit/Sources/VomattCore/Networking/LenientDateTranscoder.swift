import Foundation
import OpenAPIRuntime

/// The API mixes `2026-10-13T15:04:58.14499Z` and `2026-10-20T15:04:00Z`, so
/// decoding accepts ISO-8601 with or without fractional seconds. Encoding
/// writes whole seconds with an offset, which every endpoint accepts.
public struct LenientDateTranscoder: DateTranscoder {
    public init() {}

    public func encode(_ date: Date) throws -> String {
        date.ISO8601Format(.iso8601)
    }

    public func decode(_ string: String) throws -> Date {
        if let date = Self.parse(string) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected an ISO-8601 date, got \(string)"))
    }

    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) { return date }
        // Foundation's ISO-8601 parser takes at most millisecond precision; trim the rest
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let fractionEnd = string[string.index(after: dot)...].firstIndex { !$0.isNumber } ?? string.endIndex
        let digits = string[string.index(after: dot)..<fractionEnd]
        let trimmed = string[..<dot] + "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0) + string[fractionEnd...]
        return try? Date(String(trimmed), strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
