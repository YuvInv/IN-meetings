/// Which audio layout a recording uses (ADR-002 / ADR-011).
public enum CaptureProfile: String, Sendable, Equatable {
    /// Live call: dual-track — system audio (Core Audio process tap) + mic, kept separate.
    case call
    /// In-person meeting: a single mic track; everyone is on one mic, so "who said what" needs
    /// single-track multi-speaker diarization downstream.
    case inPerson

    public var label: String {
        switch self {
        case .call: return "call (dual-track)"
        case .inPerson: return "in-person (mic only)"
        }
    }

    /// Auto-pick from the detector's verdict (ADR-011): a live call → dual-track; otherwise in-person.
    /// Manual Start uses this rather than asking, because the audio signal already tells us which it is.
    public static func autoPick(callDetected: Bool) -> CaptureProfile {
        callDetected ? .call : .inPerson
    }
}
