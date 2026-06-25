import SwiftUI
import INMeetingsCore

/// A sheet for creating or editing a custom summary recipe. Opens from `SummarySettingsTab`.
///
/// - Creating: pass `recipe: nil`; Save calls `store.create(name:instructions:)`.
/// - Editing: pass an existing user `recipe`; Save calls `store.update(id:name:instructions:)`.
///   Delete is shown only when editing.
///
/// The caller is responsible for refreshing its recipe list on `onDismiss`.
struct RecipeEditorSheet: View {
    let store: SummaryRecipeStore
    /// The recipe being edited, or `nil` when creating a new one.
    let recipe: SummaryRecipe?
    let onDismiss: () -> Void

    @State private var name: String
    @State private var instructions: String
    @State private var validationError: String?
    @State private var showDeleteConfirm = false

    init(store: SummaryRecipeStore, recipe: SummaryRecipe?, onDismiss: @escaping () -> Void) {
        self.store = store
        self.recipe = recipe
        self.onDismiss = onDismiss
        _name         = State(initialValue: recipe.map { _ in "" } ?? "")
        _instructions = State(initialValue: "")
    }

    private var isEditing: Bool { recipe != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Edit recipe" : "New recipe")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form body
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. VC Update", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instructions")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $instructions)
                        .font(.body)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    Text("Written instructions that Claude follows when summarising this meeting. Markdown is supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = validationError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()

            Divider()

            // Action bar
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                        .confirmationDialog(
                            "Delete \"\(recipe?.displayName ?? "")\"?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) { performDelete() }
                        } message: {
                            Text("This removes the recipe permanently. Meetings that used it keep their summaries.")
                        }
                }
                Spacer()
                Button("Save") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 520)
        .onAppear {
            // Load content for the editing case (avoids fetching file in init).
            if let r = recipe {
                name         = store.displayName(id: r.id) ?? r.displayName
                instructions = store.instructions(id: r.id) ?? ""
            }
        }
    }

    // MARK: - Actions

    private func performSave() {
        validationError = nil
        do {
            if let r = recipe {
                try store.update(id: r.id, name: name, instructions: instructions)
            } else {
                try store.create(name: name, instructions: instructions)
            }
            onDismiss()
        } catch let err as SummaryRecipeStoreError {
            validationError = err.localizedDescription
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func performDelete() {
        guard let r = recipe else { return }
        try? store.delete(id: r.id)
        onDismiss()
    }
}
