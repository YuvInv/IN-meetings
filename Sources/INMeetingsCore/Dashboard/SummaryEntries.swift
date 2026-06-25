import Foundation

/// A view-model entry for one recipe's summary on a meeting — lightweight enough to be pure and
/// unit-tested independently of `RecordingStore` (which sits in the app target and can't be tested
/// in the Core bundle). The mapping + legacy fallback + selection-default logic all live here.
public struct SummaryEntry: Identifiable, Sendable, Equatable {
    /// Stable identifier — the recipe id, e.g. `"saventa-summary"`.
    public let id: String
    /// Human-readable display name, e.g. `"Saventa Summary"` or a user-chosen name.
    public let displayName: String
    /// `"running"` | `"done"` | `"failed"`
    public let state: String
    /// Set only when `state == "failed"`.
    public let error: String?

    public init(id: String, displayName: String, state: String, error: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.error = error
    }
}

// MARK: - Mapping

/// Map `[MeetingSummary]` rows to `[SummaryEntry]`, resolving display names via a name lookup and
/// ordering by `updatedAt` (most recent first — the switcher default is the newest entry).
///
/// **Legacy fallback:** when `rows` is empty but `summary.md` exists at `folderURL`, synthesise a
/// single `"saventa-summary"` entry with `state: "done"` so older meetings surface without a DB
/// migration or pipeline re-run.
///
/// - Parameters:
///   - rows: Per-recipe rows from `MeetingStore.summaries(forMeeting:)`.
///   - folderURL: The meeting package folder, used only for the legacy-fallback file check.
///   - displayName: Closure that resolves a recipe id to a human-readable name (injected so this
///     function stays pure — the caller typically calls `registry?.recipe(id:)?.displayName`).
public func makeSummaryEntries(
    rows: [MeetingSummary],
    folderURL: URL,
    displayName: (String) -> String
) -> [SummaryEntry] {
    // Sort most-recent-first (descending by the ISO-8601 updatedAt string; lexicographic sort is
    // correct because the format is zero-padded year-first).
    let sorted = rows.sorted { $0.updatedAt > $1.updatedAt }
    let mapped = sorted.map { row in
        SummaryEntry(id: row.recipeId,
                     displayName: displayName(row.recipeId),
                     state: row.state,
                     error: row.error)
    }
    guard !mapped.isEmpty else {
        // Legacy path: a meeting processed before T2 has no DB rows but may have a summary.md on disk.
        let legacyURL = folderURL.appendingPathComponent("summary.md")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return [] }
        let name = displayName("saventa-summary")
        return [SummaryEntry(id: "saventa-summary", displayName: name, state: "done")]
    }
    return mapped
}

// MARK: - Selection default

/// Pick the entry that the switcher should select by default (or after a state refresh).
///
/// Priority: keep `current` if it's still present; otherwise prefer the first `"done"` entry;
/// fall back to the first entry regardless of state.
public func defaultSelectedEntry(
    current currentId: String?,
    entries: [SummaryEntry]
) -> SummaryEntry? {
    guard !entries.isEmpty else { return nil }
    // Keep the currently-selected one if it still exists.
    if let id = currentId, let existing = entries.first(where: { $0.id == id }) {
        return existing
    }
    // Prefer the first "done" entry (most-recent-first ordering from `makeSummaryEntries`).
    if let done = entries.first(where: { $0.state == "done" }) { return done }
    return entries.first
}
