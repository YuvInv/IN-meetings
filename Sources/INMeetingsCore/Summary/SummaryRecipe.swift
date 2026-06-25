import Foundation

/// A bundled or user-supplied summary recipe — a folder containing `recipe.md` (+ optional
/// `house-style/*.md`) that `SummaryRunner` assembles into a system prompt for `claude -p`.
public struct SummaryRecipe: Sendable, Identifiable, Hashable {
    /// Stable identifier (the folder name), e.g. `"saventa-summary"`.
    public let id: String
    /// Human-readable name shown in the Settings picker, e.g. `"Saventa Summary"`.
    public let displayName: String
    /// Directory containing `recipe.md` (+ optional `house-style/` subdirectory).
    public let resourcesURL: URL
    /// `true` for recipes shipped in the app bundle; `false` for user-supplied ones in
    /// `~/Library/Application Support/IN Meetings/Recipes/`.
    public let isBuiltIn: Bool

    public init(id: String, displayName: String, resourcesURL: URL, isBuiltIn: Bool) {
        self.id = id
        self.displayName = displayName
        self.resourcesURL = resourcesURL
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Registry

/// Discovers available recipes from a bundled root and an optional user-supplied root, then
/// resolves the active recipe for `SummaryRunner`. Both roots are injected so discovery is
/// pure and unit-testable with temp directories.
public struct SummaryRecipeRegistry: Sendable {
    private let bundledRoot: URL
    private let userRoot: URL

    /// - Parameters:
    ///   - bundledRoot: The `skills/` directory inside the app bundle (immediate subdirs that
    ///     contain a `recipe.md` are treated as bundled recipes).
    ///   - userRoot: The user's custom-recipes folder (`standardUserRecipesURL` by default).
    public init(bundledRoot: URL, userRoot: URL = SummaryRecipeRegistry.standardUserRecipesURL) {
        self.bundledRoot = bundledRoot
        self.userRoot = userRoot
    }

    /// All available recipes: bundled recipes first (sorted by id), then user recipes (sorted
    /// by id). Deduped by id: bundled wins when ids collide.
    public func all() -> [SummaryRecipe] {
        var seen: Set<String> = []
        var result: [SummaryRecipe] = []
        for recipe in bundledRecipes() + userRecipes() {
            guard seen.insert(recipe.id).inserted else { continue }
            result.append(recipe)
        }
        return result
    }

    /// Look up a recipe by id.
    public func recipe(id: String) -> SummaryRecipe? {
        all().first { $0.id == id }
    }

    /// Resolve `id` → recipe, falling back to `"saventa-summary"` → first available.
    /// Returns `nil` only when the registry is completely empty.
    public func active(id: String) -> SummaryRecipe? {
        if let found = recipe(id: id) { return found }
        if let fallback = recipe(id: "saventa-summary") { return fallback }
        return all().first
    }

    // MARK: - Standard user recipes path

    /// `~/Library/Application Support/IN Meetings/Recipes/`
    public static var standardUserRecipesURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("IN Meetings/Recipes")
    }

    // MARK: - Private discovery

    private func bundledRecipes() -> [SummaryRecipe] {
        recipes(under: bundledRoot, isBuiltIn: true)
    }

    private func userRecipes() -> [SummaryRecipe] {
        recipes(under: userRoot, isBuiltIn: false)
    }

    private func recipes(under root: URL, isBuiltIn: Bool) -> [SummaryRecipe] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        return entries
            .filter { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .filter { url in
                FileManager.default.fileExists(atPath: url.appendingPathComponent("recipe.md").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let id = url.lastPathComponent
                // User recipes may carry a `name.txt` with the exact display name the user chose
                // (preserves casing/acronyms like "VC Update"). Bundled recipes have no `name.txt`.
                let nameTxtURL = url.appendingPathComponent("name.txt")
                let displayName: String
                if !isBuiltIn,
                   let stored = try? String(contentsOf: nameTxtURL, encoding: .utf8),
                   !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = stored.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    displayName = humanize(id: id)
                }
                return SummaryRecipe(id: id, displayName: displayName, resourcesURL: url, isBuiltIn: isBuiltIn)
            }
    }
}

// MARK: - Helpers

/// Convert a kebab-case recipe id into a human-readable display name, e.g.
/// `"saventa-summary"` → `"Saventa Summary"`.
private func humanize(id: String) -> String {
    id.split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
