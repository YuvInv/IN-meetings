import SwiftUI
import INMeetingsCore

/// The first-run permission wizard window: Welcome → Microphone → System Audio → Screen Recording →
/// Google → Done. Every grant step is skippable (Continue always advances; granting is optional), so the
/// user can always reach the dashboard. Screen Recording's grant needs a relaunch, which the Done step
/// front-loads via "Restart IN Meetings".
struct OnboardingWindow: View {
    @Bindable var model: OnboardingModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 18)

            Spacer(minLength: 0)
            content
                .padding(.horizontal, 32)
            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 560, height: 470)
        .background(.regularMaterial)
        .onAppear { model.refresh() }
    }

    // MARK: progress dots

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(model.screens.indices, id: \.self) { i in
                Circle()
                    .fill(i == model.index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.3)))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: per-screen content

    @ViewBuilder
    private var content: some View {
        switch model.current {
        case .welcome:
            welcome
        case .grant(.microphone):
            OnboardingStepView(
                systemImage: "mic.fill",
                title: "Microphone",
                explanation: "Lets IN Meetings record your side of a call. This is the one permission the app really needs.",
                granted: model.micGranted,
                actionLabel: "Allow Microphone",
                action: { run { await model.requestMicrophone() } },
                busy: busy)
        case .grant(.systemAudio):
            OnboardingStepView(
                systemImage: "speaker.wave.2.fill",
                title: "System Audio Recording",
                explanation: "Lets IN Meetings hear the other participants — the audio coming out of your Mac. macOS will show a prompt; choose “Allow”.",
                granted: model.systemAudioAttempted ? nil : false,
                actionLabel: "Show the prompt",
                action: { model.provokeSystemAudio() },
                note: "If you miss the prompt, you can enable IN Meetings under System Settings ▸ Privacy & Security ▸ System Audio Recording.")
        case .grant(.screenRecording):
            OnboardingStepView(
                systemImage: "video.fill",
                title: "Screen Recording",
                explanation: "Lets IN Meetings record the call window (participants and shared screen) as video. Audio-only meetings don’t need this.",
                granted: model.screenGranted,
                actionLabel: "Allow Screen Recording",
                action: { model.requestScreenRecording() },
                note: model.screenRequested && !model.screenGranted
                    ? "Granted — this takes effect after a restart (offered on the last step)."
                    : "In-person meetings are always audio-only.")
        case .grant(.google):
            googleStep
        case .done:
            done
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().aspectRatio(contentMode: .fit).frame(width: 72, height: 72)
            Text("Welcome to IN Meetings")
                .font(.largeTitle.weight(.semibold))
            Text("A quick, ~1-minute setup so the app can record your calls, transcribe them on-device, and back them up. You can skip any step and finish it later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
        }
    }

    private var googleStep: some View {
        VStack(spacing: 8) {
            OnboardingStepView(
                systemImage: "icloud.fill",
                title: "Google sign-in",
                explanation: "Backs up your recordings to Google Drive and reads your calendar to label meetings with the right company and attendees.",
                granted: model.googleConnected,
                actionLabel: "Connect Google…",
                action: { run { await model.connectGoogle() } },
                busy: busy,
                note: model.googleConnected
                    ? nil
                    : "Opens your browser to sign in. One sign-in covers both Drive and Calendar.")
            if case let .connected(email) = model.drive.status {
                Text("Connected as \(email) — pick a backup folder in Settings ▸ Drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(.green)
            Text("You’re set up")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                recapRow("Microphone", granted: model.micGranted)
                recapRow("System Audio", granted: model.systemAudioAttempted ? nil : false)
                recapRow("Screen Recording", granted: model.screenGranted, pending: model.needsRestart)
                recapRow("Google (Drive + Calendar)", granted: model.googleConnected)
                Divider().padding(.vertical, 2)
                recapRow("Auto-summary (Claude CLI)", granted: model.claudeCLIDetected,
                         pendingNote: model.claudeCLIDetected ? nil : "optional — install the Claude CLI")
            }
            .frame(maxWidth: 360, alignment: .leading)

            if model.needsRestart {
                Text("Screen Recording needs a quick restart to take effect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func recapRow(_ label: String, granted: Bool?, pending: Bool = false,
                          pendingNote: String? = nil) -> some View {
        HStack(spacing: 8) {
            switch (granted, pending) {
            case (_, true):
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
            case (.some(true), _):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case (.none, _):
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            case (.some(false), _):
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Text(label)
            if let pendingNote {
                Text("· \(pendingNote)").font(.caption).foregroundStyle(.tertiary)
            } else if pending {
                Text("· after restart").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    // MARK: footer nav

    private var footer: some View {
        HStack {
            if !model.isFirst {
                Button("Back") { model.back() }
                    .buttonStyle(.glass)
            }
            Spacer()
            if model.isLast {
                Button(model.needsRestart ? "Restart IN Meetings" : "Finish") {
                    model.finish()
                    if !model.needsRestart { dismissWindow(id: "onboarding") }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                Button(model.isFirst ? "Get started" : "Continue") { model.next() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
    }

    /// Run an async grant action with the shared busy flag.
    private func run(_ op: @escaping () async -> Void) {
        busy = true
        Task { await op(); busy = false }
    }
}
