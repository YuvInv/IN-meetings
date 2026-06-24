import AppKit
import Carbon
import CoreGraphics

/// Pastes text at the cursor in whatever app is focused, by putting it on the general pasteboard and
/// synthesizing ⌘V (A6). Synthesizing keystrokes into another app needs the **Accessibility** TCC grant
/// (`isTrusted`); when it's missing the keystroke is silently dropped by the OS, so callers gate on
/// `isTrusted` and nudge the user to grant it (decision 3 — contextual, not in onboarding).
///
/// Live-verify only (it touches the real pasteboard + CGEvent posting; not unit-tested).
public enum CursorPaste {
    /// True iff the app holds the Accessibility grant (so a synthesized ⌘V will actually land).
    public static var isTrusted: Bool { Permissions.isAccessibilityTrusted() }

    /// Set `text` on the general pasteboard, then post a ⌘V key-down/up pair to the focused app.
    /// No-op-safe: posting without the AX grant simply does nothing (the clipboard still holds `text`).
    public static func setClipboardAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()
    }

    /// Synthesize ⌘V via a private HID event source. Both events carry `.maskCommand` so the receiver sees
    /// Command held for the 'v' press (a bare key-up with the modifier keeps menu-key handling happy).
    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
