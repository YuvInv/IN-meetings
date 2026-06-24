import Carbon
import INMeetingsCore
import SwiftUI

/// Settings → Dictation: turn on global-hotkey on-device dictation (A6), pick the default language, and see
/// the two hotkey chords (rebinding deferred). Bound to `DictationSettings` (persisted via UserDefaults);
/// flipping the toggle (re)registers or tears down the chords on the live `DictationController`.
///
/// **Opt-in, default OFF.** Paste needs the Accessibility grant — handled here contextually (not in the
/// onboarding usable-floor): a status line + "Open Accessibility Settings" when it's missing.
struct DictationSettingsTab: View {
    var settings: DictationSettings
    var controller: DictationController

    /// Re-checked when the tab appears / the app reactivates, since the AX grant changes outside the app.
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dictation")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable global-hotkey dictation", isOn: Binding(
                    get: { settings.enabled },
                    set: { newValue in
                        settings.enabled = newValue
                        if newValue { controller.refreshHotKeys() } else { controller.disableHotKeys() }
                    }))
                Text("Press a hotkey to record a short mic clip, transcribe it on-device, and paste the text where your cursor is. Off by default — your meetings keep working without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.enabled {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Default language", selection: Binding(
                        get: { settings.defaultLanguage },
                        set: { settings.defaultLanguage = $0 })) {
                        Text("Hebrew").tag("he")
                        Text("English").tag("en")
                    }
                    .frame(maxWidth: 260)

                    LabeledContent("Hebrew dictation") {
                        Text(Self.chordString(keyCode: settings.heKeyCode, modifiers: settings.heModifiers))
                            .font(.body.monospaced())
                    }
                    LabeledContent("English dictation") {
                        Text(Self.chordString(keyCode: settings.enKeyCode, modifiers: settings.enModifiers))
                            .font(.body.monospaced())
                    }
                    Text("Press the same hotkey again (or the Stop button on the pill) to finish and paste. Custom shortcuts are coming soon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                accessibilitySection
            }

            Spacer()
        }
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
    }

    @ViewBuilder
    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accessibilityTrusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                Label("Accessibility access needed to paste", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Text("Pasting at the cursor synthesizes ⌘V, which macOS only allows with Accessibility access. Without it, the transcribed text is copied to your clipboard but won’t auto-paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Accessibility Settings…") { Permissions.openAccessibilitySettings() }
                    Button("Re-check") { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
                }
            }
        }
    }

    /// Render a Carbon chord (modifier mask + key code) as a glyph string, e.g. "⌃⌥⌘D".
    static func chordString(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyLabel(keyCode)
        return s
    }

    /// The display glyph for a virtual key code (the few letters/keys dictation uses by default).
    private static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        default:         return "key\(keyCode)"
        }
    }
}
