import XCTest
@testable import INMeetingsCore

/// Tests for `SummaryRecipeStore` — create/update/delete/slug/uniqueness.
/// All tests use an isolated temp directory for `userRoot`.
final class SummaryRecipeStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "recipe-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEmptyBundledRoot() throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "bundled-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - slug(from:)

    func testSlugBasicSpaces() {
        XCTAssertEqual(SummaryRecipeStore.slug(from: "VC Update"), "vc-update")
    }

    func testSlugPunctuation() {
        // "Deal: Follow-Up!" → lowercase → "deal: follow-up!" → non-alnum becomes "-" →
        // collapse → trim → "deal-follow-up"
        XCTAssertEqual(SummaryRecipeStore.slug(from: "Deal: Follow-Up!"), "deal-follow-up")
        // General invariants: no leading/trailing dashes, no empty result.
        let s = SummaryRecipeStore.slug(from: "Hello, World!")
        XCTAssertFalse(s.isEmpty)
        XCTAssertFalse(s.hasPrefix("-"))
        XCTAssertFalse(s.hasSuffix("-"))
    }

    func testSlugAllHebrew() {
        // Hebrew characters produce no Latin equivalent; result must be the fallback "recipe"
        let s = SummaryRecipeStore.slug(from: "עדכון פגישה")
        XCTAssertEqual(s, "recipe")
    }

    func testSlugAlreadyLower() {
        XCTAssertEqual(SummaryRecipeStore.slug(from: "my-recipe"), "my-recipe")
    }

    func testSlugNumeric() {
        XCTAssertEqual(SummaryRecipeStore.slug(from: "Q3 2025"), "q3-2025")
    }

    func testSlugCollapsesConsecutiveDashes() {
        let s = SummaryRecipeStore.slug(from: "  hello  world  ")
        XCTAssertEqual(s, "hello-world")
    }

    // MARK: - create

    func testCreateWritesRecipeMdAndNameTxt() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)

        let recipe = try store.create(name: "VC Update", instructions: "Summarize as bullet points.")

        // Recipe folder exists with expected id
        let expectedID = SummaryRecipeStore.slug(from: "VC Update")
        XCTAssertEqual(recipe.id, expectedID)
        XCTAssertEqual(recipe.displayName, "VC Update")
        XCTAssertFalse(recipe.isBuiltIn)

        // Files on disk
        let recipeDir = userRoot.appendingPathComponent(expectedID)
        let recipeMd = try String(contentsOf: recipeDir.appendingPathComponent("recipe.md"), encoding: .utf8)
        let nameTxt  = try String(contentsOf: recipeDir.appendingPathComponent("name.txt"),  encoding: .utf8)
        XCTAssertEqual(recipeMd, "Summarize as bullet points.")
        XCTAssertEqual(nameTxt,  "VC Update")
    }

    func testCreateDiscoverableByRegistry() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let bundledRoot = try makeEmptyBundledRoot()
        defer { try? FileManager.default.removeItem(at: bundledRoot) }

        let store = SummaryRecipeStore(userRoot: userRoot)
        try store.create(name: "VC Update", instructions: "Write bullets.")

        // The registry must discover this recipe AND surface the exact display name.
        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let all = registry.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].displayName, "VC Update")
        XCTAssertFalse(all[0].isBuiltIn)
    }

    func testCreateEmptyNameThrows() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)
        XCTAssertThrowsError(try store.create(name: "   ", instructions: "Some instructions.")) { error in
            XCTAssertEqual(error as? SummaryRecipeStoreError, .emptyName)
        }
    }

    func testCreateEmptyInstructionsThrows() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)
        XCTAssertThrowsError(try store.create(name: "My Recipe", instructions: "  ")) { error in
            XCTAssertEqual(error as? SummaryRecipeStoreError, .emptyInstructions)
        }
    }

    // MARK: - Uniqueness

    func testCreateTwoWithSameNameProducesDistinctFolders() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)

        let r1 = try store.create(name: "My Recipe", instructions: "First.")
        let r2 = try store.create(name: "My Recipe", instructions: "Second.")

        XCTAssertNotEqual(r1.id, r2.id)
        XCTAssertTrue(r2.id.hasPrefix(r1.id + "-"))
    }

    // MARK: - update

    func testUpdateKeepsIDChangesContent() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)

        let recipe = try store.create(name: "Old Name", instructions: "Old instructions.")
        let originalID = recipe.id

        try store.update(id: originalID, name: "New Name", instructions: "New instructions.")

        // ID (folder) is unchanged.
        XCTAssertEqual(store.displayName(id: originalID), "New Name")
        XCTAssertEqual(store.instructions(id: originalID), "New instructions.")

        // Original folder still exists (not renamed).
        let recipeDir = userRoot.appendingPathComponent(originalID)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: recipeDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testUpdateEmptyNameThrows() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)
        let recipe = try store.create(name: "Valid", instructions: "Initial.")
        XCTAssertThrowsError(try store.update(id: recipe.id, name: "", instructions: "Something.")) { error in
            XCTAssertEqual(error as? SummaryRecipeStoreError, .emptyName)
        }
    }

    // MARK: - delete

    func testDeleteRemovesFolder() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)

        let recipe = try store.create(name: "Temp Recipe", instructions: "Delete me.")
        try store.delete(id: recipe.id)

        let recipeDir = userRoot.appendingPathComponent(recipe.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recipeDir.path))
    }

    // MARK: - instructions / displayName

    func testInstructionsReturnsNilForMissingRecipe() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)
        XCTAssertNil(store.instructions(id: "nonexistent"))
    }

    func testDisplayNameReturnsNilForMissingRecipe() throws {
        let userRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        let store = SummaryRecipeStore(userRoot: userRoot)
        XCTAssertNil(store.displayName(id: "nonexistent"))
    }
}
