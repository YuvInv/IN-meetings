import Foundation

/// Errors thrown by `SummaryRecipeStore` operations.
public enum SummaryRecipeStoreError: Error, LocalizedError {
    case emptyName
    case emptyInstructions

    public var errorDescription: String? {
        switch self {
        case .emptyName:         return "Recipe name cannot be empty."
        case .emptyInstructions: return "Recipe instructions cannot be empty."
        }
    }
}

/// Manages user-supplied summary recipes under an injected `userRoot`.
///
/// Each recipe is stored as `<userRoot>/<slug>/recipe.md` (instructions) + `name.txt` (exact display
/// name). The `slug` is derived from the name, lowercased, spaces→`-`, stripped to `[a-z0-9-]`, and
/// made unique vs existing folder names by appending `-2`, `-3`, … when needed.
///
/// This type is pure file I/O with no SwiftUI dependency — unit-testable with any temp directory.
public struct SummaryRecipeStore: Sendable {
    private let userRoot: URL

    public init(userRoot: URL = SummaryRecipeRegistry.standardUserRecipesURL) {
        self.userRoot = userRoot
    }

    // MARK: - Create

    /// Create a new user recipe. Writes `recipe.md` + `name.txt` under a unique slug folder.
    /// - Returns: The new `SummaryRecipe` (with `isBuiltIn = false`).
    /// - Throws: `SummaryRecipeStoreError.emptyName` / `.emptyInstructions` on blank inputs,
    ///   or file-system errors.
    @discardableResult
    public func create(name: String, instructions: String) throws -> SummaryRecipe {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SummaryRecipeStoreError.emptyName }
        guard !trimmedInstructions.isEmpty else { throw SummaryRecipeStoreError.emptyInstructions }

        let id = uniqueSlug(from: trimmedName)
        let recipeDir = userRoot.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: recipeDir, withIntermediateDirectories: true)
        try trimmedInstructions.write(to: recipeDir.appendingPathComponent("recipe.md"),
                                      atomically: true, encoding: .utf8)
        try trimmedName.write(to: recipeDir.appendingPathComponent("name.txt"),
                              atomically: true, encoding: .utf8)
        return SummaryRecipe(id: id, displayName: trimmedName, resourcesURL: recipeDir, isBuiltIn: false)
    }

    // MARK: - Update

    /// Update the name and instructions of an existing recipe. The folder (id) is kept stable.
    /// - Throws: `SummaryRecipeStoreError` on blank inputs, or file-system errors.
    public func update(id: String, name: String, instructions: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw SummaryRecipeStoreError.emptyName }
        guard !trimmedInstructions.isEmpty else { throw SummaryRecipeStoreError.emptyInstructions }

        let recipeDir = userRoot.appendingPathComponent(id)
        try trimmedInstructions.write(to: recipeDir.appendingPathComponent("recipe.md"),
                                      atomically: true, encoding: .utf8)
        try trimmedName.write(to: recipeDir.appendingPathComponent("name.txt"),
                              atomically: true, encoding: .utf8)
    }

    // MARK: - Delete

    /// Remove a user recipe folder entirely.
    /// - Throws: File-system errors.
    public func delete(id: String) throws {
        let recipeDir = userRoot.appendingPathComponent(id)
        try FileManager.default.removeItem(at: recipeDir)
    }

    // MARK: - Read

    /// Read the instructions (`recipe.md`) for a user recipe. Returns `nil` if the file is missing.
    public func instructions(id: String) -> String? {
        let url = userRoot.appendingPathComponent(id).appendingPathComponent("recipe.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Read the display name (`name.txt`) for a user recipe. Returns `nil` if the file is missing.
    public func displayName(id: String) -> String? {
        let url = userRoot.appendingPathComponent(id).appendingPathComponent("name.txt")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Slug

    /// Convert a name into a URL-safe, lowercase, kebab-case slug.
    /// - Strips to `[a-z0-9-]`, collapses consecutive `-`, trims leading/trailing `-`.
    /// - Non-ASCII characters that produce no Latin equivalent are dropped; if the result is
    ///   empty (e.g. an all-Hebrew input), returns `"recipe"` as a fallback.
    public static func slug(from name: String) -> String {
        // Decompose unicode (NFD) so accented chars split into base + combining, then drop non-ASCII.
        let ascii = name
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en"))
            .lowercased()
        var result = ""
        for char in ascii.unicodeScalars {
            if char.value >= UInt32(("a" as UnicodeScalar).value) && char.value <= UInt32(("z" as UnicodeScalar).value) {
                result.append(Character(char))
            } else if char.value >= UInt32(("0" as UnicodeScalar).value) && char.value <= UInt32(("9" as UnicodeScalar).value) {
                result.append(Character(char))
            } else {
                result.append("-")
            }
        }
        // Collapse consecutive dashes and trim edges.
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "recipe" : result
    }

    // MARK: - Private

    /// Return a slug that is unique vs existing folder names under `userRoot`.
    ///
    /// Note: the snapshot→createDirectory sequence in `create` is non-atomic. A collision between
    /// two concurrent creates (e.g. two Settings windows) could theoretically produce the same
    /// folder name. This is acceptable for a single-user Settings sheet; no extra guard needed.
    private func uniqueSlug(from name: String) -> String {
        let base = Self.slug(from: name)
        let existingIDs = existingFolderNames()
        if !existingIDs.contains(base) { return base }
        var counter = 2
        while true {
            let candidate = "\(base)-\(counter)"
            if !existingIDs.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Names of all immediate subdirectories under `userRoot`.
    private func existingFolderNames() -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: userRoot, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        let dirs = entries.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        return Set(dirs.map(\.lastPathComponent))
    }
}
