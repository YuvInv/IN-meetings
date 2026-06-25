import SwiftUI
import AppKit
import INMeetingsCore

/// Settings → Summary: auto-summary toggle, active-recipe picker, and a Custom recipes list
/// where users create, edit, and delete their own recipes in-app (replacing the old
/// "Reveal custom recipes folder" flow).
///
/// Uses a `SummaryRecipeStore` for mutations and a `SummaryRecipeRegistry` (passed from the app)
/// for reading. A `refreshToken` integer is bumped on every sheet dismiss so `registry.all()` is
/// re-evaluated and both the list and the picker reflect any change.
struct SummarySettingsTab: View {
    var recipeSettings: SummaryRecipeSettings
    var capture: CaptureSettings
    var registry: SummaryRecipeRegistry

    /// Bump to force the recipe list and picker to re-read the file system after a mutation.
    @State private var refreshToken = 0
    /// The recipe being created/edited; `nil` → no sheet shown.
    @State private var editorTarget: EditorTarget?

    private let store = SummaryRecipeStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Summary")
                .font(.title2.weight(.semibold))

            // Auto-summary toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-summarize finished calls", isOn: Binding(
                    get: { capture.autoSummary },
                    set: { capture.autoSummary = $0 }))
                Text("When a call finishes, INV Meetings asks Claude to write a meeting summary — shown on the meeting and synced to Drive. Runs locally via the Claude Code CLI (requires `claude` installed and signed in). Off → summarize manually from a meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Active recipe picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Active recipe")
                    .font(.headline)

                let allRecipes = recipes()
                Picker("Recipe", selection: Binding(
                    get: { recipeSettings.activeRecipeID },
                    set: { recipeSettings.activeRecipeID = $0 })) {
                    ForEach(allRecipes) { recipe in
                        Text(recipe.displayName)
                            .tag(recipe.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
                .id(refreshToken)   // force picker to reload its options after a recipe change

                Text("The active recipe determines the style and format of summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Custom recipes section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Custom recipes")
                        .font(.headline)
                    Spacer()
                    Button("＋ New recipe") { editorTarget = .create }
                        .controlSize(.small)
                }

                let userRecipes = recipes().filter { !$0.isBuiltIn }
                if userRecipes.isEmpty {
                    Text("No custom recipes yet. Use ＋ New recipe to create one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(userRecipes) { recipe in
                            HStack {
                                Text(recipe.displayName)
                                    .lineLimit(1)
                                Spacer()
                                Button("Edit") { editorTarget = .edit(recipe) }
                                    .controlSize(.small)
                                Button("Delete") { deleteRecipe(recipe) }
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            if recipe.id != userRecipes.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editorTarget) { target in
            RecipeEditorSheet(
                store: store,
                recipe: target.recipe,
                onDismiss: {
                    editorTarget = nil
                    refreshToken += 1
                }
            )
        }
    }

    // MARK: - Helpers

    private func recipes() -> [SummaryRecipe] {
        _ = refreshToken   // depend on the token so SwiftUI re-evaluates after bumps
        return registry.all()
    }

    private func deleteRecipe(_ recipe: SummaryRecipe) {
        try? store.delete(id: recipe.id)
        refreshToken += 1
    }

    // MARK: - Editor target

    /// Identifies what the editor sheet is working on. `Identifiable` so `sheet(item:)` works.
    private enum EditorTarget: Identifiable {
        case create
        case edit(SummaryRecipe)

        var id: String {
            switch self {
            case .create:        return "create"
            case .edit(let r):   return "edit-\(r.id)"
            }
        }

        /// The recipe to pass to `RecipeEditorSheet` (`nil` for create).
        var recipe: SummaryRecipe? {
            switch self {
            case .create:        return nil
            case .edit(let r):   return r
            }
        }
    }
}
