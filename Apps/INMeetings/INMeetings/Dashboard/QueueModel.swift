import Foundation
import Observation
import INMeetingsCore

/// One row in the Queue view — a snapshot of a meeting's in-flight processing state.
struct QueueItem: Identifiable {
    var id: String { meeting.id }
    let meeting: MeetingRecord
    let state: QueueItemState
}

/// `@Observable` model for the Queue view. Holds a live view of every meeting that is currently
/// processing, recently failed, or finishing its summary — each carrying its derived `QueueItemState`
/// from `QueuePhase.derive(...)`. Wired to the same notification pair (`jobBridgeDidFinish` +
/// `summaryDidFinish`) that `RecordingStore` uses so both stay in sync.
@MainActor
@Observable
final class QueueModel {
    private(set) var items: [QueueItem] = []

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

    /// Recompute `items` from the current `RecordingStore.meetings` + live `JobBridge` state.
    /// Called on every notification + on init; also callable directly from the view's `.onAppear`.
    func reload() {
        let activeID = jobBridge.activeMeetingID
        let livePhase = jobBridge.phase
        let liveProgress = jobBridge.progress

        items = store.meetings.compactMap { meeting in
            // Show: actively processing, failed, or transcribed-with-summary-running/failed.
            // Exclude cleanly done meetings (status=transcribed, summaryState=done/nil with no
            // in-flight work) — they belong in the main list, not the queue.
            let include: Bool
            switch meeting.status {
            case "processing", "failed":
                include = true
            case "transcribed":
                include = meeting.summaryState == "running" || meeting.summaryState == "failed"
            default:
                include = false
            }
            guard include else { return nil }

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
}
