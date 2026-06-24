import SwiftUI
import AppKit
import INMeetingsCore

/// Settings → Summary: pick the active summary recipe, toggle auto-summary, and open the custom
/// recipes folder. The recipe `Picker` is driven by a `SummaryRecipeRegistry` (bundled + user recipes);
/// the selection is persisted via `SummaryRecipeSettings` to `UserDefaults` and read off the main actor
/// by `JobBridge`'s `SummaryRunner` at run time (A2).
struct SummarySettingsTab: View {
    var recipeSettings: SummaryRecipeSettings
    var capture: CaptureSettings
    var registry: SummaryRecipeRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Summary")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-summarize finished calls", isOn: Binding(
                    get: { capture.autoSummary },
                    set: { capture.autoSummary = $0 }))
                Text("When a call finishes, INV Meetings asks Claude to write a meeting summary — shown on the meeting and synced to Drive. Runs locally via the Claude Code CLI (requires `claude` installed and signed in). Off → summarize manually from a meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Active recipe")
                    .font(.headline)

                Picker("Recipe", selection: Binding(
                    get: { recipeSettings.activeRecipeID },
                    set: { recipeSettings.activeRecipeID = $0 })) {
                    ForEach(registry.all()) { recipe in
                        Text(recipe.displayName)
                            .tag(recipe.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)

                Text("The active recipe determines the style and format of summaries. Bundled recipes ship with the app; custom ones live in your Recipes folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button("Reveal custom recipes folder…") {
                    let dir = SummaryRecipeRegistry.standardUserRecipesURL
                    // Create the folder if it doesn't exist yet (first time) so Finder shows something useful.
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                .controlSize(.regular)
                Text("Drop a folder containing `recipe.md` here to add a custom recipe. It will appear in the picker on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
