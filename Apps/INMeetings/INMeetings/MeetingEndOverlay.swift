import AppKit
import SwiftUI

/// The floating "Meeting ended — stopping in Ns…" card, shown when a recorded call ends (the detector's
/// armed→idle edge). Liquid Glass surface mirroring `MeetingPromptOverlay`'s visual language. The countdown
/// is authoritative in the Core `AutoStopArbiter`; this view only renders the `remaining` the coordinator
/// pushes each second, so the bar and number can never drift from the real stop time.
struct MeetingEndOverlay: View {
    let remaining: Int
    let total: Int
    let onStopNow: () -> Void
    let onKeepRecording: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                countdownBar
                card
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
            }
            .frame(width: 380)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(10)   // breathing room inside the transparent panel for the glass halo/shadow
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meetingEnd")
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text("Meeting ended")
                    .font(.callout.weight(.semibold))
                Text("Stopping in \(remaining)s…")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("meetingEnd.countdown")

                HStack(spacing: 8) {
                    Button(action: onStopNow) {
                        Label("Stop now", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("meetingEnd.stop")

                    Button("Keep recording", action: onKeepRecording)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .accessibilityIdentifier("meetingEnd.keep")
                }
                .padding(.top, 3)
            }
        }
    }

    /// Drains left-to-right as the countdown runs (remaining / total).
    private var countdownBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18))
                Capsule().fill(.tint)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 1), value: fraction)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, Double(remaining) / Double(total))))
    }
}
