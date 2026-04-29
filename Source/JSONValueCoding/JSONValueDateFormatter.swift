import Foundation

/// ISO 8601 / RFC 3339 formatter shared by `JSONValueEncoder` and
/// `JSONValueDecoder` for handling `Date` values in tool inputs and outputs.
///
/// **Output format**: `2026-04-28T15:30:00Z` (no fractional seconds, UTC).
/// **Input formats accepted**: same, plus the fractional-seconds variant
/// (`2026-04-28T15:30:00.123Z`) and offsets (`+0500`).
///
/// This is intentionally minimal — most LLM-generated date-times come in one
/// of these two flavors. Adopters who need a different format today can wrap
/// the field in their own type with a custom Codable implementation.
internal enum JSONValueDateFormatter {

    static func string(from date: Date) -> String {
        plainFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        if let date = plainFormatter.date(from: string) {
            return date
        }
        if let date = fractionalFormatter.date(from: string) {
            return date
        }
        return nil
    }

    // ISO8601DateFormatter is thread-safe (per Apple docs) but isn't marked
    // `Sendable`. Mark these statics `nonisolated(unsafe)` since concurrent
    // reads/parses are well-defined for this Foundation type.
    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
