// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: re-skinned in macOS 26 Liquid Glass (`.glassEffect` / glass button styles) per
// DECISIONS 2026-06-14; copy/labels reworked for IN-meetings; drives off our Core Audio detector (see
// MeetingPromptCoordinator). See THIRD_PARTY_NOTICES.md.

import AppKit
import SwiftUI

/// The floating "Record now" card. Liquid Glass surface; auto-dismisses after a short window with a
/// thin countdown bar across the top, and hovering the card freezes that countdown.
struct MeetingPromptOverlay: View {
    let appLabel: String
    let onRecord: () -> Void
    let onDismiss: () -> Void
    let onSilence: () -> Void
    /// When false the card never times out (used by the debug preview).
    var autoDismiss: Bool = true

    /// How long the card stays up with no interaction.
    private let autoDismissSeconds: Double = 12
    private let tickInterval: Double = 1.0 / 30.0

    @State private var elapsed: Double = 0
    @State private var hovering = false
    @State private var done = false
    @State private var lastTick = Date()

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

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
        .onHover { hovering = $0 }
        .onReceive(timer) { _ in tick() }
        .onAppear { lastTick = Date() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meetingPrompt")
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(appLabel) — call detected")
                    .font(.callout.weight(.semibold))
                Text("Record this call with IN Meetings?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: act(onRecord)) {
                        Label("Record", systemImage: "record.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("meetingPrompt.record")

                    Button("Not now", action: act(onDismiss))
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .accessibilityIdentifier("meetingPrompt.dismiss")
                }
                .padding(.top, 3)

                Button("Don't ask for \(appLabel)", action: act(onSilence))
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                    .accessibilityIdentifier("meetingPrompt.silence")
            }
        }
    }

    private var countdownBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18))
                Capsule().fill(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: tickInterval), value: fraction)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var fraction: CGFloat {
        CGFloat(max(0, min(1, (autoDismissSeconds - elapsed) / autoDismissSeconds)))
    }

    private func tick() {
        guard !done, autoDismiss else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if hovering { return }   // freeze the countdown while the cursor is over the card
        elapsed += dt
        if elapsed >= autoDismissSeconds { fire(onDismiss) }
    }

    /// Wrap a callback so it fires at most once (Record/Not now/Silence and the auto-dismiss all race).
    private func act(_ action: @escaping () -> Void) -> () -> Void {
        { fire(action) }
    }

    private func fire(_ action: () -> Void) {
        guard !done else { return }
        done = true
        action()
    }
}
