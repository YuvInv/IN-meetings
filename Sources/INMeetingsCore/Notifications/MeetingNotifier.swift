import Foundation
import UserNotifications

/// User-facing macOS notifications for the events that happen *after* the user has moved on from a
/// meeting: transcript ready, summary ready, and processing failures (PR 1 of the v1 must-haves).
///
/// We deliberately do NOT notify on recording start/stop — the user just initiated those and is
/// watching the menu-bar timer; a banner there is noise. The value is in the asynchronous completions.
///
/// Safe to call from Core code that runs in unit tests: `post(...)` is a no-op until
/// `requestAuthorization()` has succeeded (only the app calls it) and when the binary isn't a bundled
/// app, so the existing `JobBridge` / `SummaryRunner` tests that exercise the post sites never touch
/// `UNUserNotificationCenter.current()` (which raises if there's no bundle proxy).
@MainActor
public final class MeetingNotifier {
    public static let shared = MeetingNotifier()

    /// `userInfo` key carrying the meeting id, so a notification tap can deep-link to that meeting.
    public static let meetingIDKey = "INMeetings.notification.meetingID"

    private var authorized = false
    private init() {}

    /// Request alert+sound authorization. Best-effort: a denial or an unbundled context just leaves
    /// notifications off (`post` stays a no-op). Call once from the app at launch.
    public func requestAuthorization() async {
        guard Bundle.main.bundleIdentifier != nil else { return }   // unbundled (e.g. tests) → skip
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            authorized = false
        }
    }

    /// Post a notification now. No-op until authorized (so Core unit tests never reach the center).
    /// - Parameter meetingID: when set, stored in `userInfo` so a tap opens that meeting.
    public func post(title: String, body: String, meetingID: String? = nil) {
        guard authorized, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let meetingID { content.userInfo = [Self.meetingIDKey: meetingID] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
