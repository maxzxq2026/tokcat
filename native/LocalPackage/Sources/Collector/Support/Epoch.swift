import Foundation

// Port of date_from_timestamp_ms (usage_graph.rs:2310-2318).
//
// Fork change: date buckets are UTC, not the process-local timezone. The
// 0.1.x collector mapped instants through chrono's `Local`, which shifts
// late-night UTC sessions to the next day for UTC+8 users and makes the
// graph depend on the machine's zone. The offset math is kept (instead of
// a bare civil-date conversion) so parity runs against the legacy Rust
// collector — mirrored to Utc on its side — compare identical buckets.

/// Fixed UTC. Parity runs of tokcat-dump against the legacy Rust collector
/// compare identical UTC buckets on both sides.
private let utcTimeZone = TimeZone(secondsFromGMT: 0)!

func dateFromTimestampMs(_ timestampMs: Int64) -> String {
    let instant = Date(timeIntervalSince1970: Double(timestampMs) / 1000.0)
    let offset = Int64(utcTimeZone.secondsFromGMT(for: instant))
    let localSecs = floorDiv(timestampMs, 1000) + offset
    let days = floorDiv(localSecs, 86_400)
    let (y, m, d) = civilFromDays(Int(days))
    return String(format: "%04d-%02d-%02d", y, m, d)
}

func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    if (a % b != 0) && ((a < 0) != (b < 0)) { return q - 1 }
    return q
}
