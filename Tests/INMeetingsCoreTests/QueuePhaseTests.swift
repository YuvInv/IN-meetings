import XCTest
@testable import INMeetingsCore

/// Unit tests for `QueuePhase.derive(...)` — the pure pipeline-phase derivation function (decision 3,
/// A3). No UI, no async, no disk: just the state machine logic.
final class QueuePhaseTests: XCTestCase {

    // MARK: - Failed pipeline

    func testFailedStatusReturnsFailed() {
        let state = QueuePhase.derive(
            status: "failed",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: nil, isActive: false)
        XCTAssertEqual(state, .failed)
    }

    func testFailedStatusIgnoresIsActive() {
        let state = QueuePhase.derive(
            status: "failed",
            pipelinePhase: "transcribing", pipelineProgress: 0.3,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .failed)
    }

    // MARK: - Processing + active (live pipeline phases)

    func testProcessingActiveTranscribing() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "transcribing", pipelineProgress: 0.2,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .transcribing(progress: 0.2))
        XCTAssertEqual(state.progress, 0.2)
        XCTAssertEqual(state.label, "Transcribing")
    }

    func testProcessingActiveDiarizing() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "diarizing", pipelineProgress: 0.65,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .diarizing(progress: 0.65))
        XCTAssertEqual(state.progress, 0.65)
    }

    func testProcessingActivePackaging() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "packaging", pipelineProgress: 0.9,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .packaging(progress: 0.9))
        XCTAssertEqual(state.progress, 0.9)
    }

    func testProcessingActivePipelinePhaseQueued() {
        // status.json phase == "queued" means the pipeline acknowledged the job but hasn't started yet
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "queued", pipelineProgress: 0.0,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .queued)
    }

    func testProcessingActiveNilProgressDefaultsToZero() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "transcribing", pipelineProgress: nil,
            summaryState: nil, isActive: true)
        XCTAssertEqual(state, .transcribing(progress: 0))
    }

    // MARK: - Processing + not active (waiting in queue)

    func testProcessingInactiveReturnsQueued() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: "transcribing", pipelineProgress: 0.5,
            summaryState: nil, isActive: false)
        XCTAssertEqual(state, .queued)
    }

    func testProcessingInactiveNilPhaseReturnsQueued() {
        let state = QueuePhase.derive(
            status: "processing",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: nil, isActive: false)
        XCTAssertEqual(state, .queued)
    }

    // MARK: - Transcribed + summary states

    func testTranscribedNoSummaryReturnsDone() {
        let state = QueuePhase.derive(
            status: "transcribed",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: nil, isActive: false)
        XCTAssertEqual(state, .done)
    }

    func testTranscribedSummaryRunningReturnsSummarizing() {
        let state = QueuePhase.derive(
            status: "transcribed",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: "running", isActive: false)
        XCTAssertEqual(state, .summarizing)
    }

    func testTranscribedSummaryDoneReturnsDone() {
        let state = QueuePhase.derive(
            status: "transcribed",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: "done", isActive: false)
        XCTAssertEqual(state, .done)
    }

    func testTranscribedSummaryFailedReturnsSummaryFailed() {
        let state = QueuePhase.derive(
            status: "transcribed",
            pipelinePhase: nil, pipelineProgress: nil,
            summaryState: "failed", isActive: false)
        XCTAssertEqual(state, .summaryFailed)
    }

    // MARK: - Labels and progress helpers

    func testQueuedLabel() {
        XCTAssertEqual(QueueItemState.queued.label, "Queued")
        XCTAssertNil(QueueItemState.queued.progress)
    }

    func testSummarizingLabel() {
        XCTAssertEqual(QueueItemState.summarizing.label, "Summarizing")
        XCTAssertNil(QueueItemState.summarizing.progress)
    }

    func testFailedLabel() {
        XCTAssertEqual(QueueItemState.failed.label, "Failed")
    }

    func testSummaryFailedLabel() {
        XCTAssertEqual(QueueItemState.summaryFailed.label, "Summary failed")
    }

    func testDoneLabel() {
        XCTAssertEqual(QueueItemState.done.label, "Done")
    }
}
