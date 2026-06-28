import AppKit
import INMeetingsCore
import SwiftUI

/// Floats the recording HUD whenever `RecordingController` is recording. Edge-triggered show/hide on the
/// idle↔recording transition (polled at ~5 Hz); the hosted SwiftUI view runs its own 20 Hz meter tick. The
/// panel is a non-activating `NSPanel` at `.statusBar` level so it floats over everything without stealing
/// focus and never covers the call window (bottom-center, above the Dock). Mirrors
/// `DictationOverlayCoordinator` / `MeetingEndCoordinator`.
@available(macOS 14.2, *)
@MainActor
final class RecordingHUDCoordinator {
    private let recorder: RecordingController
    private var panel: NSPanel?
    private var pollTimer: Timer?

    init(recorder: RecordingController) { self.recorder = recorder }

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hide()
    }

    private func tick() {
        if recorder.isRecording {
            if panel == nil { show() }
        } else if panel != nil {
            hide()
        }
    }

    private func show() {
        let host = NSHostingView(rootView: RecordingHUDHost(
            recorder: recorder,
            onTogglePause: { [weak self] in self?.recorder.togglePause() },
            onStop: { [weak self] in self?.recorder.stop() }))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
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
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Bottom-center, above the Dock — a HUD position out of the call-window's way.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 80))
    }
}
