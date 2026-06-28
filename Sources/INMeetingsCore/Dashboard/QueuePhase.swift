import Foundation

/// The processing state of one meeting as seen in the Queue view.
///
/// Derived via `QueuePhase.derive(...)` — a pure function that collapses the four status fields
/// (store status, live pipeline phase, summary state, and whether this job is the one currently
/// running) into a single displayable state + 0–1 progress fraction. No SwiftUI import.
public enum QueueItemState: Equatable, Sendable {
    /// The meeting is waiting in the serialisation queue behind another active job.
    case queued
    /// Actively transcribing audio (pipeline phase: transcribing).
    case transcribing(progress: Double)
    /// Diarizing speakers (pipeline phase: diarizing).
    case diarizing(progress: Double)
    /// Assembling the context package (pipeline phase: packaging).
    case packaging(progress: Double)
    /// The Claude summary is running.
    case summarizing
    /// Pipeline transcription failed — show Reveal + Retry.
    case failed
    /// Summary failed but transcript succeeded — partial; show summary Retry.
    case summaryFailed
    /// All done (transcribed + summary done or no summary configured).
    case done

    /// Human-readable label for display in the Queue row.
    public var label: String {
        switch self {
        case .queued:               return "Queued"
        case .transcribing:         return "Transcribing"
        case .diarizing:            return "Diarizing"
        case .packaging:            return "Packaging"
        case .summarizing:          return "Summarizing"
        case .failed:               return "Failed"
        case .summaryFailed:        return "Summary failed"
        case .done:                 return "Done"
        }
    }

    /// 0–1 progress fraction, or nil when progress is indeterminate.
    public var progress: Double? {
        switch self {
        case .transcribing(let p): return p
        case .diarizing(let p):    return p
        case .packaging(let p):    return p
        default:                   return nil
        }
    }

    /// Label with a percentage appended when progress is determinate, e.g. "Transcribing 40%".
    public var detailedLabel: String {
        if let p = progress { return "\(label) \(Int((p * 100).rounded()))%" }
        return label
    }
}

/// Namespace for the pipeline-phase derivation function.
public enum QueuePhase {
    /// Derive the `QueueItemState` for one meeting row.
    ///
    /// - Parameters:
    ///   - status: The store status string: `"processing"` | `"transcribed"` | `"failed"`.
    ///   - pipelinePhase: The live pipeline phase from `JobBridge.phase` (nil until a job starts).
    ///   - pipelineProgress: The live 0–1 fraction from `JobBridge.progress` (nil = unknown).
    ///   - summaryState: From `MeetingRecord.summaryState`: `"running"` | `"done"` | `"failed"` | nil.
    ///   - isActive: True only for the meeting whose id matches `JobBridge.activeMeetingID`. When
    ///     false and `status == "processing"`, the meeting is waiting behind the running job.
    public static func derive(
        status: String,
        pipelinePhase: String?,
        pipelineProgress: Double?,
        summaryState: String?,
        isActive: Bool
    ) -> QueueItemState {
        switch status {
        case "failed":
            return .failed

        case "processing":
            guard isActive, let phase = pipelinePhase else { return .queued }
            let p = pipelineProgress ?? 0
            switch phase {
            case "transcribing": return .transcribing(progress: p)
            case "diarizing":    return .diarizing(progress: p)
            case "packaging":    return .packaging(progress: p)
            default:             return .queued      // "queued" phase from status.json → still waiting
            }

        case "transcribed":
            switch summaryState {
            case "running": return .summarizing
            case "failed":  return .summaryFailed
            default:        return .done
            }

        default:
            // "done" or any unexpected status — treat as done.
            return .done
        }
    }
}
