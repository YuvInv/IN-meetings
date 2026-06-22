import SwiftUI

/// Reusable content chrome for one grant step of the onboarding wizard: an icon, a title, a plain-language
/// explanation, a status pill, the (single, prominent) grant action button, an optional note, and an
/// optional secondary "Open … settings" link. Presentational only — the wizard's navigation (Back /
/// Continue / Skip) lives in `OnboardingWindow`.
struct OnboardingStepView: View {
    let systemImage: String
    let title: String
    let explanation: String
    /// nil = status can't be read; true = granted; false = not yet.
    let granted: Bool?
    let actionLabel: String
    let action: () -> Void
    var busy = false
    var note: String?
    /// Optional secondary action (e.g. a System Settings deep-link) shown as a quiet link below the note.
    var secondaryLabel: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tint)
                .frame(height: 56)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            statusPill

            Button(action: action) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(actionLabel)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(busy || granted == true)

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel, action: secondaryAction)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch granted {
        case .some(true):
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
        case .some(false):
            Label("Not yet granted", systemImage: "circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .none:
            Label("Approve the prompt when it appears", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
