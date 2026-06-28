import Foundation

/// In-place text edits to a meeting's `transcript.json` — the dashboard "fix a line" and "find & replace
/// a recurring name" actions. Mirrors `SpeakerEditor`: read the raw JSON, modify the `utterances` array's
/// `text` fields, rewrite with sorted keys, and return the new bytes for the Drive re-upload + FTS
/// re-index (the same write-through path speaker renaming already uses).
///
/// Addressing by array index is safe here: text edits and find-&-replace never reorder or resize the
/// utterance list, and the view's `pkg.utterances` decodes the same on-disk order.
public enum TranscriptEditor {
    enum EditError: Error, LocalizedError {
        case noUtterances
        case indexOutOfRange
        var errorDescription: String? {
            switch self {
            case .noUtterances: return "transcript.json has no utterances array"
            case .indexOutOfRange: return "utterance index out of range"
            }
        }
    }

    /// Replace the text of the utterance at `index` in `folder`'s `transcript.json`. Returns the rewritten
    /// file bytes (for Drive re-upload). Throws if the transcript can't be read/written or the index is bad.
    @discardableResult
    public static func setUtteranceText(_ newText: String, at index: Int, in folder: URL) throws -> Data {
        let url = folder.appendingPathComponent("transcript.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              var utterances = json["utterances"] as? [[String: Any]] else {
            throw EditError.noUtterances
        }
        guard utterances.indices.contains(index) else { throw EditError.indexOutOfRange }
        utterances[index]["text"] = newText
        json["utterances"] = utterances
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return data
    }

    /// Replace every occurrence of `find` with `replaceWith` across all utterance texts. Returns the
    /// rewritten bytes + the number of occurrences replaced (only writes the file when count > 0).
    @discardableResult
    public static func findAndReplace(find: String, replaceWith: String, caseSensitive: Bool,
                                      in folder: URL) throws -> (data: Data, count: Int) {
        let url = folder.appendingPathComponent("transcript.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              var utterances = json["utterances"] as? [[String: Any]] else {
            throw EditError.noUtterances
        }
        let bytesUnchanged = { try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) }
        guard !find.isEmpty else { return (try bytesUnchanged(), 0) }

        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var total = 0
        for i in utterances.indices {
            guard let text = utterances[i]["text"] as? String, !text.isEmpty else { continue }
            let (replaced, n) = replacingAndCounting(in: text, find: find, with: replaceWith, options: options)
            if n > 0 { utterances[i]["text"] = replaced; total += n }
        }
        guard total > 0 else { return (try bytesUnchanged(), 0) }
        json["utterances"] = utterances
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return (data, total)
    }

    /// Replace `find` with `repl` in `text` (range-based so case-insensitive matches replace literally),
    /// returning the new string + the replacement count. `find` is assumed non-empty.
    static func replacingAndCounting(in text: String, find: String, with repl: String,
                                     options: String.CompareOptions) -> (String, Int) {
        var result = ""
        var count = 0
        var cursor = text.startIndex
        while let range = text.range(of: find, options: options, range: cursor..<text.endIndex) {
            result += text[cursor..<range.lowerBound]
            result += repl
            count += 1
            cursor = range.upperBound
        }
        guard count > 0 else { return (text, 0) }
        result += text[cursor...]
        return (result, count)
    }
}
