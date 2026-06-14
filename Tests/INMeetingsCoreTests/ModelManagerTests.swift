import XCTest
import CryptoKit
@testable import INMeetingsCore

@available(macOS 14.2, *)
final class ModelManagerTests: XCTestCase {
    func testStreamingSHA256MatchesKnownVector() throws {
        // "abc" → the canonical SHA-256 test vector.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(try ModelManager.sha256(ofFileAt: tmp),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testStreamingSHA256HandlesMultiChunkFile() throws {
        // > 1 MiB so the 1 MiB-chunk reader loops more than once; compare against CryptoKit one-shot.
        var bytes = Data(count: 3 * (1 << 20) + 17)
        for i in bytes.indices { bytes[i] = UInt8(i & 0xff) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try ModelManager.sha256(ofFileAt: tmp), expected)
    }

    func testCatalogEntryIsPinned() {
        let m = ModelCatalog.hebrewTurbo
        XCTAssertEqual(m.filename, "ivrit-large-v3-turbo.ggml.bin")
        XCTAssertEqual(m.sizeBytes, 1_624_555_275)
        XCTAssertEqual(m.sha256, "c8090411113357097bfafc2b8e228ec1639fa7f5fe4ecb5d054ac0ccef8641b1")
        XCTAssertEqual(m.sha256.count, 64)
        XCTAssertEqual(m.url.scheme, "https")
        XCTAssertEqual(m.url.host, "huggingface.co")
    }

    func testInstalledModelURLLivesUnderApplicationSupport() {
        let url = ModelManager.installedModelURL
        XCTAssertEqual(url.lastPathComponent, "ivrit-large-v3-turbo.ggml.bin")
        XCTAssertTrue(url.path.contains("IN Meetings/Models"),
                      "expected the model under Application Support/IN Meetings/Models, got \(url.path)")
    }
}
