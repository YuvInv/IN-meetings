import Foundation

/// Builds the synthetic `job.json` for an imported recording (ADR-009 contract, mirrored in `pipeline/
/// job.py`). An import is always a single mixed track → `profile: "inPerson"` (the only profile that
/// diarizes one track into N speakers) and `tracks.mic` points at the normalized WAV. The extra
/// `source: "imported"` key is read back at index time (MeetingStore) for provenance; `Job.load` ignores
/// it. Kept pure for testability.
public enum ImportJob {
    public static func make(meetingId: String, directory: URL, audioFilename: String,
                            startedAt: Date, endedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "meeting_id": meetingId,
            "directory": directory.path,
            "profile": "inPerson",
            "tracks": ["mic": audioFilename],
            "started_at": iso.string(from: startedAt),
            "ended_at": iso.string(from: endedAt),
            "created_at": iso.string(from: endedAt),
            "video": false,
            "source": "imported",
        ]
    }
}
