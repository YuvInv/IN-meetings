import Foundation

public struct MeetingDateBucket: Sendable { public let label: String; public let items: [MeetingRecord] }

public func filterMeetings(_ recs: [MeetingRecord], search: String) -> [MeetingRecord] {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return recs }
    return recs.filter {
        ($0.company ?? "").lowercased().contains(q) || ($0.title ?? "").lowercased().contains(q)
            || $0.id.lowercased().contains(q)
    }
}

/// Meetings with no resolved company — surfaced under "Needs linking" so the user can fix the match.
public func needsLinking(_ recs: [MeetingRecord]) -> [MeetingRecord] {
    recs.filter { ($0.company ?? "").isEmpty }
}

/// Meetings still being processed (pipeline not done, or not yet synced). A terminal `"failed"` is NOT
/// "processing" — it has its own bucket so a stuck-looking spinner never hides a real failure.
public func processing(_ recs: [MeetingRecord]) -> [MeetingRecord] {
    recs.filter { $0.status != "failed"
        && ($0.status != "done" || $0.syncState == "syncing" || $0.syncState == "local") }
}

/// Meetings whose pipeline failed — surfaced so a failed transcription is visible, not silently dropped.
public func failed(_ recs: [MeetingRecord]) -> [MeetingRecord] {
    recs.filter { $0.status == "failed" }
}

/// Group meetings (newest first) into Today / Yesterday / weekday / long-date buckets.
public func bucketMeetingsByDate(_ recs: [MeetingRecord], now: Date) -> [MeetingDateBucket] {
    let iso = ISO8601DateFormatter()
    let cal = Calendar.current
    let weekday = DateFormatter(); weekday.dateFormat = "EEEE"
    let long = DateFormatter(); long.dateStyle = .long
    func date(_ r: MeetingRecord) -> Date { iso.date(from: r.startedAt) ?? .distantPast }
    let sorted = recs.sorted { date($0) > date($1) }
    var order: [String] = []; var map: [String: [MeetingRecord]] = [:]
    for r in sorted {
        let d = date(r)
        let key: String = cal.isDateInToday(d) ? "Today"
            : cal.isDateInYesterday(d) ? "Yesterday"
            : (cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 99) < 7
              ? weekday.string(from: d) : long.string(from: d)
        if map[key] == nil { order.append(key) }
        map[key, default: []].append(r)
    }
    return order.map { MeetingDateBucket(label: $0, items: map[$0]!) }
}

/// Index of the utterance covering `time` (its `[start, end)` window), or nil between/after utterances.
/// Drives the transcript seek-highlight in the meeting detail view.
public func activeUtteranceIndex(in utterances: [TranscriptPackage.Utterance], at time: Double) -> Int? {
    utterances.firstIndex { time >= $0.start && time < $0.end }
}
