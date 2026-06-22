import AppKit
import SwiftUI
import INMeetingsCore

/// Floats the "Meeting ended — stopping in Ns…" countdown card when a recorded call ends, and stops the
/// recording if the countdown elapses. The symmetric counterpart of `MeetingPromptCoordinator` (which
/// offers to *start* on the idle→armed edge); this offers to *stop* on the armed→idle edge.
///
/// All the timing/decision logic lives in the pure `AutoStopArbiter` (Core, unit-tested). This coordinator
/// is the thin app-layer shell: a 1 s timer drives the arbiter, and it owns the floating non-activating
/// `NSPanel`. A stop only ever happens through the visible countdown (`.stopNow`) — never silently.
@available(macOS 14.2, *)
@MainActor
final class MeetingEndCoordinator {
    private let detector: CallDetector
    private let recorder: RecordingController
    private let settings: MeetingDetectionSettings
    private var arbiter: AutoStopArbiter

    private var panel: NSPanel?
    private var host: NSHostingView<MeetingEndOverlay>?
    private var pollTimer: Timer?

    /// - Parameters mirror the start coordinator; `debounceSeconds`/`countdownSeconds` are injectable so a
    ///   future Settings knob (or a test) can tune them. Defaults match the spec (12 s / 30 s).
    init(detector: CallDetector, recorder: RecordingController, settings: MeetingDetectionSettings,
         debounceSeconds: Int = 12, countdownSeconds: Int = 30) {
        self.detector = detector
        self.recorder = recorder
        self.settings = settings
        self.arbiter = AutoStopArbiter(debounceTicks: debounceSeconds, countdownTicks: countdownSeconds)
    }

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so we're already on the main actor here.
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hide()
    }

    private func tick() {
        switch arbiter.tick(status: detector.state.status,
                            isRecording: recorder.isRecording,
                            enabled: settings.autoStopEnabled) {
        case .none:
            break
        case .showCountdown(let remaining):
            showOrUpdate(remaining: remaining)
        case .hide:
            hide()
        case .stopNow:
            recorder.stop()
            hide()
        }
    }

    private func makeOverlay(remaining: Int) -> MeetingEndOverlay {
        MeetingEndOverlay(
            remaining: remaining,
            total: arbiter.countdownTicks,
            onStopNow: { [weak self] in
                self?.arbiter.recordingStopped()
                self?.recorder.stop()
                self?.hide()
            },
            onKeepRecording: { [weak self] in
                self?.arbiter.keepRecording()
                self?.hide()
            })
    }

    /// First `.showCountdown` presents the panel; subsequent ones just swap the rendered `remaining`.
    private func showOrUpdate(remaining: Int) {
        if let host {
            host.rootView = makeOverlay(remaining: remaining)
            return
        }
        present(makeOverlay(remaining: remaining))
    }

    private func present(_ overlay: MeetingEndOverlay) {
        let host = NSHostingView(rootView: overlay)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
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
        self.host = host
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        self.host = nil
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
    private var previewTimer: Timer?

    /// Visual-test hook: float the countdown card and run a self-contained countdown — WITHOUT touching the
    /// arbiter or the recorder (the buttons just dismiss). Lets you eyeball the card without staging a real
    /// call-end. Mirrors `MeetingPromptCoordinator.previewPrompt()`.
    func previewCountdown() {
        previewTimer?.invalidate()
        var remaining = arbiter.countdownTicks
        present(previewOverlay(remaining: remaining))
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                remaining -= 1
                if remaining <= 0 { self.previewTimer?.invalidate(); self.hide() }
                else if let host = self.host { host.rootView = self.previewOverlay(remaining: remaining) }
            }
        }
    }

    private func previewOverlay(remaining: Int) -> MeetingEndOverlay {
        MeetingEndOverlay(
            remaining: remaining,
            total: arbiter.countdownTicks,
            onStopNow: { [weak self] in self?.previewTimer?.invalidate(); self?.hide() },
            onKeepRecording: { [weak self] in self?.previewTimer?.invalidate(); self?.hide() })
    }
#endif
}
