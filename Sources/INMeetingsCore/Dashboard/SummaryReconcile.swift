import Foundation

/// Delete one recipe's summary from a meeting and re-establish a coherent post-delete state.
///
/// Deleting a summary touches three places that must stay in sync, and getting any one wrong makes the
/// delete look like a no-op (T3 review finding):
///   1. the per-recipe row in `meetingSummary` (the authoritative list),
///   2. the per-recipe file `summaries/<recipeId>.md`,
///   3. the rollup (`meeting.summaryState`/`summaryError`) + the `summary.md` **mirror** of the
///      most-recent *done* summary — both legacy/back-compat surfaces.
///
/// Concretely, after removing recipe `recipeId` from meeting `meetingId` (package at `folder`):
///   - **No rows remain:** delete `summary.md` and clear the rollup (`updateSummaryState(state: nil, …)`),
///     so `makeSummaryEntries` returns nothing (no phantom legacy entry) and the Queue/Processing view
///     (which keys off `summaryState`) doesn't stay pinned.
///   - **Rows remain:** set the rollup to the *most-recent remaining* row's state+error, and re-mirror
///     `summary.md` from the most-recent remaining **done** row's file (or remove it if no done row remains).
///
/// Pure orchestration over `MeetingStore` + the filesystem so it can be unit-tested with a temp store +
/// temp folder; `RecordingStore.deleteSummary` is a thin caller. Best-effort on the filesystem side (a
/// missing file is fine); store errors propagate.
public func reconcileAfterSummaryDelete(
    store: MeetingStore,
    meetingId: String,
    recipeId: String,
    folder: URL
) throws {
    // 1. Drop the per-recipe row and its file.
    try store.deleteSummary(meetingId: meetingId, recipeId: recipeId)
    let fm = FileManager.default
    let summariesDir = folder.appendingPathComponent("summaries")
    try? fm.removeItem(at: summariesDir.appendingPathComponent("\(recipeId).md"))

    // 2. Recompute the rollup + the summary.md mirror from what's left.
    //    `summaries(forMeeting:)` is ascending by updatedAt, so the most-recent row is `.last`.
    let remaining = try store.summaries(forMeeting: meetingId)
    let mirrorURL = folder.appendingPathComponent("summary.md")

    guard let latest = remaining.last else {
        // No summaries left: clear the rollup and drop the mirror so no phantom legacy entry survives.
        try store.updateSummaryState(id: meetingId, state: nil, error: nil, sessionId: nil)
        try? fm.removeItem(at: mirrorURL)
        return
    }

    // Some remain: the rollup tracks the most-recent remaining run's state+error.
    try store.updateSummaryState(id: meetingId, state: latest.state, error: latest.error, sessionId: nil)

    // Re-mirror summary.md from the most-recent remaining *done* summary (matching SummaryRunner's
    // "mirror of the most-recently-completed summary" contract). If none is done, remove the stale mirror.
    try? fm.removeItem(at: mirrorURL)
    if let latestDone = remaining.last(where: { $0.state == "done" }) {
        let doneFile = summariesDir.appendingPathComponent("\(latestDone.recipeId).md")
        try? fm.copyItem(at: doneFile, to: mirrorURL)
    }
}
