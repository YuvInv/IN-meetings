import XCTest
@testable import INMeetingsCore

final class VocabStoreTests: XCTestCase {
    private func tempFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vocab-\(UUID().uuidString).json")
    }

    func testLearnAppendsNewEntryAndMergesVariants() throws {
        let store = VocabStore(url: tempFile())
        try store.learn(canonical: "Anthropic", variant: "אנתרופיק")
        try store.learn(canonical: "Anthropic", variant: "antropic")   // merge into the same canonical
        try store.learn(canonical: "Anthropic", variant: "antropic")   // duplicate → deduped
        try store.learn(canonical: "Haiku", variant: "הייקו")           // new canonical

        let entries = store.load()
        XCTAssertEqual(entries.count, 2)
        let anthropic = try XCTUnwrap(entries.first { $0.canonical == "Anthropic" })
        XCTAssertEqual(Set(anthropic.variants), ["אנתרופיק", "antropic"])
    }

    func testLearnIgnoresBlankOrIdentical() throws {
        let store = VocabStore(url: tempFile())
        try store.learn(canonical: "X", variant: "X")     // identical → no-op
        try store.learn(canonical: "  ", variant: "y")    // blank canonical → no-op
        try store.learn(canonical: "z", variant: "")      // blank variant → no-op
        XCTAssertTrue(store.load().isEmpty)
    }

    func testWritesShapeCompatibleWithPipeline() throws {
        let url = tempFile()
        try VocabStore(url: url).learn(canonical: "Anthropic", variant: "אנתרופיק")
        // Same `[{canonical, variants}]` shape the Python pipeline (`load_user_vocab`) reads.
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        XCTAssertEqual(json.first?["canonical"] as? String, "Anthropic")
        XCTAssertEqual(json.first?["variants"] as? [String], ["אנתרופיק"])
    }
}
