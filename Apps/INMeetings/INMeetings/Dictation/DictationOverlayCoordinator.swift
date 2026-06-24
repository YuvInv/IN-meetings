// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: hosts the Liquid Glass DictationOverlay pill in a non-activating panel; shows it
// while DictationController is active (A6) instead of Mila's record-prompt-on-window-title. See
// THIRD_PARTY_NOTICES.md.

import AppKit
import INMeetingsCore
import SwiftUI

/// Floats the dictation status pill whenever `DictationController.state != idle`.
///
/// Edge-triggered show/hide on the idle↔active transition (polled at ~10 Hz so the pill appears promptly
/// when the hotkey fires). The hosted SwiftUI view observes the `@Observable` controller directly, so the
/// live mic meter + state text update without rebuilding the panel. The panel is a non-activating `NSPanel`
/// at `.statusBar` level so it floats over everything and never steals focus from the app you're typing in.
@MainActor
final class DictationOverlayCoordinator {
    private let controller: DictationController

    private var panel: NSPanel?
    private var pollTimer: Timer?

    init(controller: DictationController) {
        self.controller = controller
    }

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hide()
    }

    private func tick() {
        if controller.isActive {
            if panel == nil { show() }
        } else if panel != nil {
            hide()
        }
    }

    private func show() {
        let host = NSHostingView(rootView: DictationPillHost(controller: controller) { [weak self] in
            self?.controller.stop()
        })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
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

    /// Bottom-center of the main screen (above the Dock) — a HUD-style position out of the typing area.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 80))
    }
}

/// SwiftUI wrapper that observes the `@Observable` `DictationController` so the pill's state re-renders in
/// place (the panel is built once per active session). The mic `level` is read through to the recorder's
/// running peak — not an observable stored property — so a lightweight 20 Hz tick refreshes the meter
/// while listening (the same Timer.publish pattern as the record-prompt countdown).
private struct DictationPillHost: View {
    var controller: DictationController
    let onStop: () -> Void

    @State private var tick = 0
    private let meterTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DictationOverlay(state: controller.state, level: controller.level, onStop: onStop)
            .onReceive(meterTimer) { _ in
                // Touch @State only while listening so the meter animates; idle/transcribing don't churn.
                if case .recording = controller.state { tick &+= 1 }
            }
    }
}
