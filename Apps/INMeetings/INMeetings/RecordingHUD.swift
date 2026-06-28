import INMeetingsCore
import SwiftUI

/// A compact Liquid Glass HUD that floats while recording — the "we really are capturing this" trust
/// signal. Shows a recording dot + elapsed timer, per-track live level meters (Me always; Them on a call),
/// and Pause/Stop. "Pause" mutes capture to a silent gap (the file stays continuous); the paused state is
/// visually distinct (amber pause glyph, dimmed meters). This glass is CHROME (a floating panel), which is
/// the correct place for `.glassEffect` per the macOS 26 HIG.
struct RecordingHUD: View {
    let elapsed: String
    let profile: CaptureProfile
    let isPaused: Bool
    let micDB: Float
    let systemDB: Float?
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
                    .font(.title3)
                    .foregroundStyle(isPaused ? AnyShapeStyle(.orange) : AnyShapeStyle(.red))
                    .symbolEffect(.pulse, isActive: !isPaused)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(isPaused ? "Paused" : "Recording").font(.callout.weight(.semibold))
                        Text(elapsed).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    meters
                }

                Button(action: onTogglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.glass).controlSize(.small)
                .accessibilityIdentifier("recordingHUD.pause")
                .help(isPaused ? "Resume recording" : "Pause recording")

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.glassProminent).controlSize(.small)
                .accessibilityIdentifier("recordingHUD.stop")
                .help("Stop recording")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(10)   // breathing room for the glass halo inside the transparent panel
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recordingHUD")
    }

    private var meters: some View {
        VStack(alignment: .leading, spacing: 3) {
            meterRow("Me", db: micDB)
            if profile == .call, let systemDB { meterRow("Them", db: systemDB) }
        }
        .opacity(isPaused ? 0.4 : 1)   // dimmed while paused — a clear "not recording" cue
    }

    @ViewBuilder private func meterRow(_ label: String, db: Float) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            LevelBar(db: db).frame(width: 120)
        }
    }
}

/// Observes the `@Observable` `RecordingController` so state/elapsed/pause re-render in place, and ticks a
/// 20 Hz timer so the live level meters (read through to the recorder, not stored observable props) animate.
struct RecordingHUDHost: View {
    var recorder: RecordingController
    let onTogglePause: () -> Void
    let onStop: () -> Void

    @State private var tick = 0
    private let meterTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let profile: CaptureProfile = {
            if case let .recording(p, _) = recorder.state { return p }
            return .inPerson
        }()
        RecordingHUD(elapsed: recorder.elapsedString, profile: profile, isPaused: recorder.isPaused,
                     micDB: recorder.currentMicDB, systemDB: recorder.currentSystemDB,
                     onTogglePause: onTogglePause, onStop: onStop)
            .onReceive(meterTimer) { _ in
                // Touch @State only while actually recording (and not paused) so the meters animate.
                if recorder.isRecording && !recorder.isPaused { tick &+= 1 }
            }
    }
}
