import XCTest
@testable import INMeetingsCore

/// The Google Picker HTML is assembled in Core (testable) and seeded with the per-user OAuth token.
final class DriveConfigTests: XCTestCase {
    func testPickerHTMLEmbedsTokenAppIDAndBridge() {
        let html = DriveConfig.pickerHTML(token: "ya29.TEST-TOKEN")
        XCTAssertTrue(html.contains("ya29.TEST-TOKEN"))               // the user's OAuth token is seeded
        XCTAssertTrue(html.contains(DriveConfig.pickerAppID))          // the GCP project number
        XCTAssertTrue(html.contains("google.picker.PickerBuilder"))    // the Picker is built
        XCTAssertTrue(html.contains("setSelectFolderEnabled"))         // folders are selectable
        XCTAssertTrue(html.contains("messageHandlers.picker"))         // JS → Swift bridge
    }

    func testPickerAppIDMatchesOAuthProjectNumber() {
        // The Picker app id is the numeric project prefix of the OAuth client id.
        XCTAssertTrue(DriveConfig.oauth.clientID.hasPrefix(DriveConfig.pickerAppID + "-"))
    }
}
