import Foundation

/// User-taught spelling corrections, learned from the dashboard's find-&-replace "remember this for
/// future meetings" toggle. Written here by the app and read by the Python pipeline's post-correction
/// (`postcorrect.correct`) so a fix made once auto-applies to every later transcript.
///
/// Same shape as the pipeline's `context.vocab.json`, so the two merge trivially:
/// `[{ "canonical": "Anthropic", "variants": ["אנתרופיק", ...] }]`.
///
/// Default path: `~/Library/Application Support/IN Meetings/vocab-corrections.json`. The
/// `IN_MEETINGS_VOCAB_CORRECTIONS` env var overrides it — the pipeline honors the same override, which
/// keeps the Swift writer and the Python reader in sync (and lets tests point at a temp file).
public struct VocabStore {
    /// Env override shared with the Python pipeline (`load_user_vocab`).
    public static let envKey = "IN_MEETINGS_VOCAB_CORRECTIONS"

    public struct Entry: Codable, Equatable, Sendable {
        public var canonical: String
        public var variants: [String]
        public init(canonical: String, variants: [String]) {
            self.canonical = canonical
            self.variants = variants
        }
    }

    public let url: URL

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else if let env = ProcessInfo.processInfo.environment[Self.envKey], !env.isEmpty {
            self.url = URL(fileURLWithPath: env)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.url = base.appendingPathComponent("IN Meetings/vocab-corrections.json")
        }
    }

    public func load() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// Teach "`variant` should read as `canonical`". Merges into an existing canonical entry (de-duping
    /// variants) or appends a new one. No-op when either side is blank or they're identical.
    public func learn(canonical: String, variant: String) throws {
        let canon = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canon.isEmpty, !v.isEmpty, canon != v else { return }

        var entries = load()
        if let i = entries.firstIndex(where: { $0.canonical == canon }) {
            if !entries[i].variants.contains(v) { entries[i].variants.append(v) }
        } else {
            entries.append(Entry(canonical: canon, variants: [v]))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // UTF-8; Hebrew is not escaped
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}
