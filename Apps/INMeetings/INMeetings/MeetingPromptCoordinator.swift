// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: triggers off OUR Core Audio `CallDetector` (app-agnostic, no Screen Recording)
// instead of Mila's Zoom-only window-title poll; observes the idle→armed edge; hosts the Liquid Glass
// MeetingPromptOverlay in a non-activating panel. See THIRD_PARTY_NOTICES.md.

import AppKit
import SwiftUI
import INMeetingsCore

/// Shows the floating "Record now" card the moment a live call is detected.
///
/// Edge-triggered: a single prompt fires on each `idle → armed` transition of `CallDetector` (so leaving
/// and rejoining a call re-prompts), subject to the user's enabled / snooze / per-app settings. The
/// detector polls every 2 s; this coordinator polls it at 1 s to catch the edge quickly. The panel is a
/// non-activating `NSPanel` floating over everything (incl. fullscreen Zoom/Meet) so it never steals the
/// call's focus.
@MainActor
final class MeetingPromptCoordinator {
    private let detector: CallDetector
    private let recorder: RecordingController
    private let settings: MeetingDetectionSettings

    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var lastStatus: DetectionState.Status = .idle

    init(detector: CallDetector, recorder: RecordingController, settings: MeetingDetectionSettings) {
        self.detector = detector
        self.recorder = recorder
        self.settings = settings
    }

    func start() {
        // Seed as .idle (not the current status) so a call that's ALREADY active when the app launches
        // registers as an idle→armed edge on the first poll and still prompts — opening IN-meetings
        // mid-call is exactly when you want the offer. (Our detector only arms on a real bidirectional
        // call, so this can't false-fire just because a meeting app is open.)
        lastStatus = .idle
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        #if DEBUG
        // Visual-test hook: launch with IN_MEETINGS_PREVIEW_PROMPT=1 to float the card immediately.
        if ProcessInfo.processInfo.environment["IN_MEETINGS_PREVIEW_PROMPT"] != nil {
            DispatchQueue.main.async { [weak self] in self?.previewPrompt() }
        }
        #endif
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hide()
    }

    private func tick() {
        // If recording started by any other means while the card is up, dismiss it.
        if panel != nil, recorder.isRecording { hide() }

        let now = detector.state.status
        defer { lastStatus = now }
        guard now == .armed, lastStatus != .armed else { return }   // the idle → armed edge
        maybePrompt()
    }

    private func maybePrompt() {
        guard panel == nil,
              !recorder.isRecording,
              settings.promptEnabled,
              !settings.isSnoozed else { return }
        let label = detector.state.callApps.first ?? "Call"
        guard !settings.isDisabled(app: label) else { return }
        show(label: label)
    }

    private func show(label: String) {
        present(MeetingPromptOverlay(
            appLabel: label,
            onRecord: { [weak self] in
                self?.hide()
                // Starting while the detector is armed makes RecordingController auto-pick the `call`
                // profile → dual-track (mic + system), which is the whole point of the prompt.
                Task { @MainActor [weak self] in await self?.recorder.start() }
            },
            onDismiss: { [weak self] in
                self?.settings.snooze()
                self?.hide()
            },
            onSilence: { [weak self] in
                self?.settings.disable(app: label)
                self?.hide()
            }))
    }

    /// Build the floating panel around an overlay and fade it in.
    private func present(_ overlay: MeetingPromptOverlay) {
        let host = NSHostingView(rootView: overlay)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 184),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false   // Liquid Glass renders its own halo/shadow
        panel.isMovableByWindowBackground = false
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 16,
                                     y: visible.maxY - size.height - 16))
    }

#if DEBUG
    /// Force-show the card for visual testing, bypassing detection — and WITHOUT touching real settings:
    /// the buttons just close the card (no snooze / disable / start-recording side effects). Stays up
    /// until dismissed. (Earlier the preview's "Not now" ran the real `snooze()`, silencing prompts for
    /// an hour and making a subsequent real call look like it failed to auto-trigger.)
    func previewPrompt(label: String = "Google Chrome (Meet)") {
        present(MeetingPromptOverlay(
            appLabel: label,
            onRecord: { [weak self] in self?.hide() },
            onDismiss: { [weak self] in self?.hide() },
            onSilence: { [weak self] in self?.hide() },
            autoDismiss: false))
    }
#endif
}
