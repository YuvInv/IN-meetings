import XCTest
@testable import INMeetingsCore

/// Tests for `SummaryRecipeRegistry` and `SummaryRecipe` discovery.
/// The registry is pure (injectable roots), so all tests use temp directories — no bundle lookups.
final class SummaryRecipeRegistryTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir(name: String) throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write a minimal `recipe.md` so the directory passes the discovery filter.
    private func addRecipe(named id: String, to root: URL) throws -> URL {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# \(id) recipe".write(to: dir.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Create a subdir WITHOUT recipe.md — the registry must exclude it.
    private func addDirWithoutRecipe(named name: String, to root: URL) throws {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "some file".write(to: dir.appendingPathComponent("not-a-recipe.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Discovery

    func testDiscoveryIncludesOnlyDirsWithRecipeMd() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "alpha-summary", to: bundledRoot)
        try addRecipe(named: "beta-summary", to: bundledRoot)
        try addDirWithoutRecipe(named: "no-recipe-dir", to: bundledRoot)   // must be excluded

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let all = registry.all()

        XCTAssertEqual(all.map(\.id).sorted(), ["alpha-summary", "beta-summary"])
        XCTAssertTrue(all.allSatisfy(\.isBuiltIn))
    }

    func testUserRecipesAppendedAfterBuiltIn() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "bundled-one", to: bundledRoot)
        try addRecipe(named: "user-one", to: userRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let all = registry.all()

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all[0].isBuiltIn)    // bundled first
        XCTAssertFalse(all[1].isBuiltIn)   // user after
    }

    func testDeduplicationBundledWins() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        // Same id in both — bundled must win (appear once, isBuiltIn = true)
        try addRecipe(named: "shared-id", to: bundledRoot)
        try addRecipe(named: "shared-id", to: userRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let all = registry.all()

        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isBuiltIn)
    }

    func testRecipeById() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "alpha-summary", to: bundledRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        XCTAssertNotNil(registry.recipe(id: "alpha-summary"))
        XCTAssertNil(registry.recipe(id: "not-there"))
    }

    func testDisplayNameHumanization() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "saventa-summary", to: bundledRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let recipe = registry.recipe(id: "saventa-summary")
        XCTAssertEqual(recipe?.displayName, "Saventa Summary")
    }

    // MARK: - active(id:) fallback

    func testActiveReturnsById() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "alpha-summary", to: bundledRoot)
        try addRecipe(named: "beta-summary", to: bundledRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        XCTAssertEqual(registry.active(id: "beta-summary")?.id, "beta-summary")
    }

    func testActiveFallsBackToSaventaSummary() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "alpha-summary", to: bundledRoot)
        try addRecipe(named: "saventa-summary", to: bundledRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        // Unknown id → fall back to saventa-summary
        XCTAssertEqual(registry.active(id: "unknown-id")?.id, "saventa-summary")
    }

    func testActiveFallsBackToFirstAvailableWhenNoSaventa() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        try addRecipe(named: "brief-summary", to: bundledRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        // Unknown id + no saventa-summary → first available
        XCTAssertEqual(registry.active(id: "unknown-id")?.id, "brief-summary")
    }

    func testActiveReturnsNilForEmptyRegistry() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        XCTAssertNil(registry.active(id: "anything"))
    }

    // MARK: - name.txt display-name override

    func testUserRecipeWithNameTxtUsesStoredName() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        // Create a user recipe folder with recipe.md + name.txt
        let recipeDir = userRoot.appendingPathComponent("vc-update")
        try FileManager.default.createDirectory(at: recipeDir, withIntermediateDirectories: true)
        try "Summarize bullets.".write(to: recipeDir.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)
        try "VC Update".write(to: recipeDir.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let recipe = registry.recipe(id: "vc-update")
        XCTAssertEqual(recipe?.displayName, "VC Update")   // exact casing from name.txt
    }

    func testUserRecipeWithoutNameTxtFallsBackToHumanize() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        // No name.txt — only recipe.md
        try addRecipe(named: "deal-summary", to: userRoot)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let recipe = registry.recipe(id: "deal-summary")
        XCTAssertEqual(recipe?.displayName, "Deal Summary")   // humanize fallback
    }

    func testBundledRecipeIgnoresNameTxt() throws {
        let bundledRoot = try makeTempDir(name: "bundled")
        defer { try? FileManager.default.removeItem(at: bundledRoot) }
        let userRoot = try makeTempDir(name: "user")
        defer { try? FileManager.default.removeItem(at: userRoot) }

        // Even if someone puts a name.txt in a bundled folder, bundled recipes stay humanized.
        let recipeDir = try addRecipe(named: "saventa-summary", to: bundledRoot)
        try "Override Name".write(to: recipeDir.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)

        let registry = SummaryRecipeRegistry(bundledRoot: bundledRoot, userRoot: userRoot)
        let recipe = registry.recipe(id: "saventa-summary")
        XCTAssertEqual(recipe?.displayName, "Saventa Summary")   // humanize, not the override
    }
}
