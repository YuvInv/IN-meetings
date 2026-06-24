import Foundation
import Observation
import INMeetingsCore

/// One row in the Queue view — a snapshot of a meeting's in-flight processing state.
struct QueueItem: Identifiable {
    var id: String { meeting.id }
    let meeting: MeetingRecord
    let state: QueueItemState
}

/// `@Observable` model for the Queue view. Holds a stored snapshot of every meeting that is currently
/// processing, recently failed, or finishing its summary, refreshed on the same notification pair
/// (`jobBridgeDidFinish` + `summaryDidFinish`) that `RecordingStore` uses so both stay in sync.
///
/// `items` is **computed**, not stored: it reads the live `JobBridge.phase` / `progress` /
/// `activeMeetingID` (which the `watchStatus` timer updates ~every 0.5s with no notification) and
/// derives each row's state on the fly. Because `QueueView.body` iterates `model.items`, those live
/// reads happen during `body` evaluation — so SwiftUI's `@Observable` tracking registers them as view
/// dependencies and re-renders the active row's phase label + progress bar on every tick, without a
/// terminal event or a chatty per-tick notification.
@MainActor
@Observable
final class QueueModel {
    /// Snapshot of the meetings that belong in the queue, refreshed on store/DB changes. The live
    /// pipeline phase is *not* baked in here — it's applied in `items` so the bar animates per tick.
    private(set) var meetings: [MeetingRecord] = []

    private let store: RecordingStore
    private let jobBridge: JobBridge
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: RecordingStore, jobBridge: JobBridge) {
        self.store = store
        self.jobBridge = jobBridge
        reload()
        for name in [Notification.Name.jobBridgeDidFinish, .summaryDidFinish] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Live rows for the Queue view. Computed (not stored) so the reads of `jobBridge.activeMeetingID`
    /// / `phase` / `progress` happen during `QueueView.body` evaluation — letting SwiftUI track them and
    /// re-render each ~0.5s `watchStatus` tick. The active meeting gets the live phase/progress; every
    /// other in-flight meeting derives as "Queued".
    var items: [QueueItem] {
        let activeID = jobBridge.activeMeetingID
        let livePhase = jobBridge.phase
        let liveProgress = jobBridge.progress
        return meetings.map { meeting in
            let isActive = meeting.id == activeID
            let state = QueuePhase.derive(
                status: meeting.status,
                pipelinePhase: isActive ? livePhase : nil,
                pipelineProgress: isActive ? liveProgress : nil,
                summaryState: meeting.summaryState,
                isActive: isActive)
            return QueueItem(meeting: meeting, state: state)
        }
    }

    /// Refresh the `meetings` snapshot from `RecordingStore.meetings`. Called on every notification + on
    /// init; also callable directly from the view's `.onAppear`. Filtering only (no live pipeline read) —
    /// the live phase/progress is layered on in `items`.
    func reload() {
        meetings = store.meetings.filter { meeting in
            // Show: actively processing, failed, or transcribed-with-summary-running/failed.
            // Exclude cleanly done meetings (status=transcribed, summaryState=done/nil with no
            // in-flight work) — they belong in the main list, not the queue.
            switch meeting.status {
            case "processing", "failed":
                return true
            case "transcribed":
                return meeting.summaryState == "running" || meeting.summaryState == "failed"
            default:
                return false
            }
        }
    }
}
