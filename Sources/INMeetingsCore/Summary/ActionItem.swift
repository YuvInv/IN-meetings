import Foundation

/// A single structured action item / next step extracted from a meeting by a summary recipe (PR 7).
///
/// Read-only in v1: these are recipe *output* (a JSON sidecar written alongside the prose summary), not
/// app-editable state. `id` is derived deterministically from `task`+`owner` (Swift's `String.hashValue`
/// is per-process-randomized, so we use a stable FNV-1a hash) — a re-run of the same recipe yields the
/// same ids for unchanged items.
public struct ActionItem: Codable, Sendable, Identifiable, Equatable {
    public var task: String
    /// The person responsible, if the recipe identified one.
    public var owner: String?
    /// One of: `open` | `in-progress` | `done` | `blocked`. Unknown values render as `open`.
    public var status: String
    /// ISO-8601 date string, or nil when no due date was stated.
    public var dueDate: String?

    /// Stable identity from task+owner so reloads/re-runs keep the same id for unchanged items.
    public var id: String { Self.deterministicID(task: task, owner: owner) }

    // `id` is derived, never decoded from / encoded to the recipe-emitted JSON.
    enum CodingKeys: String, CodingKey { case task, owner, status, dueDate }

    public init(task: String, owner: String? = nil, status: String = "open", dueDate: String? = nil) {
        self.task = task
        self.owner = owner
        self.status = status
        self.dueDate = dueDate
    }

    /// Deterministic, process-stable FNV-1a hash over `task` + `owner`.
    public static func deterministicID(task: String, owner: String?) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (task + "\u{1}" + (owner ?? "")).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// The action-items sidecar a recipe writes to `summaries/<recipeId>-actions.json`. `recipeId` and
/// `generatedAt` are tolerated-missing so a minimal `{"items": [...]}` still decodes.
public struct ActionItems: Codable, Sendable, Equatable {
    public var recipeId: String?
    public var generatedAt: String?
    public var items: [ActionItem]

    public init(recipeId: String? = nil, generatedAt: String? = nil, items: [ActionItem]) {
        self.recipeId = recipeId
        self.generatedAt = generatedAt
        self.items = items
    }
}

/// Loads a recipe's action-items sidecar from a meeting package. Returns nil when the file is absent or
/// malformed (a recipe that doesn't emit it, or an older run) so callers degrade gracefully to no section.
public enum ActionItemsLoader {
    public static func load(forMeetingFolder folder: URL, recipeId: String) -> ActionItems? {
        let url = folder.appendingPathComponent("summaries/\(recipeId)-actions.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActionItems.self, from: data)
    }
}
