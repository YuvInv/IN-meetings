// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: re-skinned in macOS 26 Liquid Glass (`.glassEffect`) per DECISIONS 2026-06-14;
// repurposed from the record-prompt card into a compact dictation status pill driven by our
// DictationController state machine (A6). See THIRD_PARTY_NOTICES.md.

import INMeetingsCore
import SwiftUI

/// A small Liquid Glass pill that floats while dictation is active: a live mic-level meter + a one-line
/// status ("Listening… / Transcribing… / Pasted"). Purely a status surface — the hotkey (or the Stop
/// button) drives the flow.
struct DictationOverlay: View {
    let state: DictationController.State
    /// Live mic peak in dBFS while listening (drives the meter fill).
    let level: Float
    let onStop: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.callout.weight(.semibold))
                    if isListening {
                        meter
                    }
                }
                if isListening {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("dictation.stop")
                    .help("Stop and transcribe")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(10)   // breathing room for the glass halo/shadow inside the transparent panel
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dictationPill")
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.title3)
            .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            .symbolEffect(.pulse, isActive: isListening)
            .frame(width: 22)
    }

    /// A simple level meter: maps the −60…0 dBFS peak to a 0…1 fill.
    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18))
                Capsule().fill(.tint)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.08), value: fraction)
            }
        }
        .frame(width: 120, height: 4)
    }

    private var fraction: CGFloat {
        // −60 dBFS (near silence) → 0, 0 dBFS (clipping) → 1.
        CGFloat(max(0, min(1, (Double(level) + 60) / 60)))
    }

    private var isListening: Bool { if case .recording = state { return true }; return false }
    private var isFailed: Bool { if case .failed = state { return true }; return false }

    private var iconName: String {
        switch state {
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .done:         return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        case .idle:         return "mic"
        }
    }

    private var statusText: String {
        switch state {
        case .recording:               return "Listening…"
        case .transcribing:            return "Transcribing…"
        case .done:                    return "Pasted"
        case .failed(let message):     return message
        case .idle:                    return ""
        }
    }
}
