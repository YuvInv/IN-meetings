import Foundation

/// Builds shareable Markdown / HTML documents for a finished meeting (PR 4 of the v1 must-haves).
///
/// Pure and value-in/value-out so it's unit-testable: the builders take the already-decoded package
/// models, and the `folder:` convenience reads `transcript.json` / `metadata.json` / `summary.md` off
/// disk (so edited speaker names and any future transcript edits are reflected). The HTML builder is
/// what the app renders to PDF via `WKWebView.createPDF`; it sets `dir="rtl"` for a Hebrew transcript so
/// the PDF reads correctly right-to-left.
public enum MeetingExport {

    // MARK: - Public builders (from models)

    /// A Markdown document: header (company/title/date/duration/type/attendees) → summary (if any) →
    /// speaker-labeled, `[HH:MM:SS]`-timestamped transcript.
    public static func markdown(transcript: TranscriptPackage,
                                metadata: MeetingMetadata?,
                                company: String?,
                                fallbackTitle: String?,
                                durationSeconds: Double?,
                                summary: String?) -> String {
        let title = resolvedTitle(metadata: metadata, fallback: fallbackTitle)
        let heading = firstNonEmpty(company, metadata?.company?.name, title) ?? "Meeting"
        let names = speakerNames(transcript)

        var lines: [String] = ["# \(heading)", ""]
        lines.append("**Title:** \(title)  ")
        if let date = displayDate(metadata?.meeting.start) { lines.append("**Date:** \(date)  ") }
        if let durationSeconds { lines.append("**Duration:** \(clock(durationSeconds))  ") }
        lines.append("**Type:** \(typeLabel(metadata?.meeting.type))  ")
        if let attendees = metadata?.attendees, !attendees.isEmpty {
            let list = attendees.map { att in att.email.map { "\(att.name) (\($0))" } ?? att.name }
            lines.append("**Attendees:** \(list.joined(separator: ", "))  ")
        }
        lines.append("")

        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        lines.append("## Transcript")
        lines.append("")
        if transcript.utterances.isEmpty {
            lines.append("_No transcript._")
        } else {
            for u in transcript.utterances {
                let who = names[u.speakerId] ?? u.speakerId
                lines.append("[\(clock(u.start))] **\(who):** \(u.text)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A standalone HTML document for PDF rendering. `dir="rtl"` when the transcript language is Hebrew.
    public static func html(transcript: TranscriptPackage,
                            metadata: MeetingMetadata?,
                            company: String?,
                            fallbackTitle: String?,
                            durationSeconds: Double?,
                            summary: String?) -> String {
        let dir = transcript.language == "he" ? "rtl" : "ltr"
        let title = resolvedTitle(metadata: metadata, fallback: fallbackTitle)
        let heading = firstNonEmpty(company, metadata?.company?.name, title) ?? "Meeting"
        let names = speakerNames(transcript)

        var meta: [String] = ["<p class=\"meta\">"]
        meta.append("<strong>Title:</strong> \(esc(title))<br>")
        if let date = displayDate(metadata?.meeting.start) { meta.append("<strong>Date:</strong> \(esc(date))<br>") }
        if let durationSeconds { meta.append("<strong>Duration:</strong> \(clock(durationSeconds))<br>") }
        meta.append("<strong>Type:</strong> \(esc(typeLabel(metadata?.meeting.type)))<br>")
        if let attendees = metadata?.attendees, !attendees.isEmpty {
            let list = attendees.map { att in att.email.map { "\(att.name) (\($0))" } ?? att.name }
            meta.append("<strong>Attendees:</strong> \(esc(list.joined(separator: ", ")))")
        }
        meta.append("</p>")

        var transcriptHTML = "<h2>Transcript</h2>"
        if transcript.utterances.isEmpty {
            transcriptHTML += "<p><em>No transcript.</em></p>"
        } else {
            for u in transcript.utterances {
                let who = names[u.speakerId] ?? u.speakerId
                transcriptHTML += "<p class=\"line\"><span class=\"ts\">[\(clock(u.start))]</span> "
                    + "<strong>\(esc(who)):</strong> \(esc(u.text))</p>"
            }
        }

        var summaryHTML = ""
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryHTML = "<h2>Summary</h2><pre class=\"summary\">\(esc(summary))</pre>"
        }

        return """
        <!DOCTYPE html>
        <html dir="\(dir)" lang="\(esc(transcript.language))">
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 13px;
                 color: #1d1d1f; margin: 32px; line-height: 1.5; }
          h1 { font-size: 22px; margin: 0 0 12px; }
          h2 { font-size: 16px; margin: 24px 0 8px; border-bottom: 1px solid #d2d2d7; padding-bottom: 4px; }
          .meta { color: #3a3a3c; font-size: 12px; }
          .line { margin: 0 0 6px; }
          .ts { color: #86868b; font-variant-numeric: tabular-nums; }
          .summary { white-space: pre-wrap; font-family: inherit; background: #f5f5f7;
                     padding: 12px; border-radius: 8px; }
        </style>
        </head>
        <body>
        <h1>\(esc(heading))</h1>
        \(meta.joined())
        \(summaryHTML)
        \(transcriptHTML)
        </body>
        </html>
        """
    }

    // MARK: - Convenience (from a package folder)

    /// Read the package off disk and build Markdown. Returns nil if the transcript can't be read.
    public static func markdown(folder: URL, company: String?, fallbackTitle: String?,
                                durationSeconds: Double?) -> String? {
        guard let transcript = try? PackageReader.transcript(in: folder) else { return nil }
        return markdown(transcript: transcript, metadata: try? PackageReader.metadata(in: folder),
                        company: company, fallbackTitle: fallbackTitle,
                        durationSeconds: durationSeconds, summary: readSummary(folder))
    }

    /// Read the package off disk and build HTML. Returns nil if the transcript can't be read.
    public static func html(folder: URL, company: String?, fallbackTitle: String?,
                            durationSeconds: Double?) -> String? {
        guard let transcript = try? PackageReader.transcript(in: folder) else { return nil }
        return html(transcript: transcript, metadata: try? PackageReader.metadata(in: folder),
                    company: company, fallbackTitle: fallbackTitle,
                    durationSeconds: durationSeconds, summary: readSummary(folder))
    }

    /// A filesystem-safe filename stem like `Acme - Intro call - 2026-06-25`.
    public static func filenameStem(company: String?, title: String?, startedAtISO: String?) -> String {
        let parts = [firstNonEmpty(company, title) ?? "Meeting", isoDateOnly(startedAtISO)].compactMap { $0 }
        let raw = parts.joined(separator: " - ")
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: illegal).joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "Meeting" : cleaned
    }

    // MARK: - Helpers

    private static func readSummary(_ folder: URL) -> String? {
        try? String(contentsOf: folder.appendingPathComponent("summary.md"), encoding: .utf8)
    }

    /// Map speaker id → display name (assigned name, else the raw id like "Speaker 1").
    private static func speakerNames(_ transcript: TranscriptPackage) -> [String: String] {
        var map: [String: String] = [:]
        for sp in transcript.speakers { if let n = sp.name, !n.isEmpty { map[sp.id] = n } }
        return map
    }

    private static func resolvedTitle(metadata: MeetingMetadata?, fallback: String?) -> String {
        firstNonEmpty(metadata?.meeting.title, fallback) ?? "Meeting"
    }

    private static func typeLabel(_ type: String?) -> String {
        type == "in_person" ? "In-person" : "Call"
    }

    /// `[HH:MM:SS]` body uses this without brackets; always hour-padded for stable column width.
    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// ISO-8601 → "MMM d, yyyy 'at' h:mm a" in a fixed POSIX locale (deterministic for tests); falls back
    /// to the raw string when it can't be parsed.
    static func displayDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let parsers = [isoWithFraction, isoPlain]
        let date = parsers.lazy.compactMap { $0.date(from: iso) }.first
        guard let date else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return out.string(from: date)
    }

    private static func isoDateOnly(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        return String(iso.prefix(10))   // yyyy-MM-dd
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Minimal HTML escaping for text interpolated into the PDF document.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
