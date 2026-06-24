import XCTest
@testable import INMeetingsCore

@MainActor
final class SummaryRecipeSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "summary-recipe-\(UUID().uuidString)")!
    }

    func testDefaultIsSaventaSummary() {
        let s = SummaryRecipeSettings(defaults: freshDefaults())
        XCTAssertEqual(s.activeRecipeID, "saventa-summary")
    }

    func testPersistsAcrossReload() {
        let d = freshDefaults()
        let s = SummaryRecipeSettings(defaults: d)
        s.activeRecipeID = "brief-summary"
        let reloaded = SummaryRecipeSettings(defaults: d)
        XCTAssertEqual(reloaded.activeRecipeID, "brief-summary")
    }

    func testNonisolatedStaticActiveRecipeIDDefaultsToSaventa() {
        let d = freshDefaults()
        XCTAssertEqual(SummaryRecipeSettings.activeRecipeID(d), "saventa-summary")
    }

    func testNonisolatedStaticActiveRecipeIDReadsPersistedValue() {
        let d = freshDefaults()
        d.set("custom-recipe", forKey: SummaryRecipeSettings.Keys.activeRecipe)
        XCTAssertEqual(SummaryRecipeSettings.activeRecipeID(d), "custom-recipe")
    }

    func testStringHelperReturnsDefault() {
        let d = freshDefaults()
        XCTAssertEqual(SummaryRecipeSettings.string(d, "missing", default: "my-default"), "my-default")
    }

    func testStringHelperReturnsPersistedValue() {
        let d = freshDefaults()
        d.set("persisted", forKey: "my-key")
        XCTAssertEqual(SummaryRecipeSettings.string(d, "my-key", default: "my-default"), "persisted")
    }
}
