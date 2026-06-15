import Foundation

/// Swift-side mirror of the frozen context-package contract (`schema/transcript.schema.json` +
/// `schema/metadata.schema.json`, ADR-005). Decodes what the Python pipeline writes; the SQLite index
/// (ADR-006) and the dashboard (ADR-007) read these.
///
/// Forward-compatible by construction: `JSONDecoder` ignores unknown keys, and every field that a
/// later phase populates (Phase-2 calendar/CRM, V1 video, ASR confidence) is `Optional`, so a v1 MVP
/// package and a fully-enriched one both decode.
public struct TranscriptPackage: Decodable, Sendable {
    public struct Speaker: Decodable, Sendable {
        public let id: String
        public let side: String
        public let track: String?
        public let name: String?
        public let email: String?
    }

    public struct Utterance: Decodable, Sendable {
        public let text: String
        public let start: Double
        public let end: Double
        public let speakerId: String
        public let confidence: Double?

        public init(text: String, start: Double, end: Double, speakerId: String, confidence: Double?) {
            self.text = text
            self.start = start
            self.end = end
            self.speakerId = speakerId
            self.confidence = confidence
        }
    }

    public let meetingId: String?
    public let profile: String?
    public let language: String
    public let engine: String?
    public let modelRevision: String?
    public let biased: Bool?
    public let diarized: Bool?
    public let speakers: [Speaker]
    public let utterances: [Utterance]
}

/// The `metadata.json` sidecar (ADR-005). Calendar/CRM/consent fields are `Optional` because they are
/// null/empty until the Phase-2 context assembler fills them.
public struct MeetingMetadata: Decodable, Sendable {
    public struct Meeting: Decodable, Sendable {
        public let title: String?
        public let start: String   // ISO-8601
        public let end: String     // ISO-8601
        public let type: String    // "call" | "in_person"
        public let calendarEventId: String?
    }

    public struct Attendee: Decodable, Sendable {
        public let name: String
        public let email: String?
        public let side: String
        public let matchedCrmContactId: String?
    }

    public struct Company: Decodable, Sendable {
        public let name: String?
        public let sevantaDealId: String?
        public let dealigenceId: String?
        public let matched: Bool
    }

    public struct Recording: Decodable, Sendable {
        public let durations: [String: Double]?
        public let tracks: [String]
        public let sampleRate: Int?
        public let captureSourceApp: String?
        public let video: Bool
    }

    public struct Transcription: Decodable, Sendable {
        public let engine: String
        public let modelRevision: String
        public let language: String
        public let biased: Bool
        public let vocabularyTermsUsed: [String]?
    }

    public struct Consent: Decodable, Sendable {
        public let status: String              // verbal | calendar-notice | none | internal
        public let jurisdictionHint: String?
    }

    public let schemaVersion: String
    public let meeting: Meeting
    public let attendees: [Attendee]?
    public let company: Company?
    public let recording: Recording
    public let transcription: Transcription
    public let consent: Consent?
}

/// Reads a context-package folder (ADR-005 layout) into the typed models above.
public enum PackageReader {
    /// The decoder for every package file: snake_case JSON → camelCase Swift, matching the schemas.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func transcript(in folder: URL) throws -> TranscriptPackage {
        let data = try Data(contentsOf: folder.appendingPathComponent("transcript.json"))
        return try makeDecoder().decode(TranscriptPackage.self, from: data)
    }

    public static func metadata(in folder: URL) throws -> MeetingMetadata {
        let data = try Data(contentsOf: folder.appendingPathComponent("metadata.json"))
        return try makeDecoder().decode(MeetingMetadata.self, from: data)
    }
}
