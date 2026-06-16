import XCTest
@testable import INMeetingsCore

final class SpeakerEditorTests: XCTestCase {
    private func freshTranscriptDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"meeting_id":"m","language":"he","speakers":[
          {"id":"Me","side":"internal","track":"mic"},
          {"id":"Speaker 1","side":"external","track":"system"}],
         "utterances":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("transcript.json"))
        return dir
    }

    func testSetNameAssignsAndLeavesOthersUntouched() throws {
        let dir = try freshTranscriptDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SpeakerEditor.setName("shirley", email: "shirley@altahq.com", speakerId: "Speaker 1", in: dir)
        let pkg = try PackageReader.transcript(in: dir)
        let s1 = pkg.speakers.first { $0.id == "Speaker 1" }
        XCTAssertEqual(s1?.name, "shirley")
        XCTAssertEqual(s1?.email, "shirley@altahq.com")
        XCTAssertNil(pkg.speakers.first { $0.id == "Me" }?.name)   // untouched
    }

    func testClearNameRemovesIt() throws {
        let dir = try freshTranscriptDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SpeakerEditor.setName("Gil", speakerId: "Speaker 1", in: dir)
        XCTAssertEqual(try PackageReader.transcript(in: dir).speakers.first { $0.id == "Speaker 1" }?.name, "Gil")
        _ = try SpeakerEditor.setName(nil, speakerId: "Speaker 1", in: dir)            // clear
        XCTAssertNil(try PackageReader.transcript(in: dir).speakers.first { $0.id == "Speaker 1" }?.name)
    }

    func testBlankNameIsTreatedAsClear() throws {
        let dir = try freshTranscriptDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SpeakerEditor.setName("   ", speakerId: "Speaker 1", in: dir)
        XCTAssertNil(try PackageReader.transcript(in: dir).speakers.first { $0.id == "Speaker 1" }?.name)
    }
}
