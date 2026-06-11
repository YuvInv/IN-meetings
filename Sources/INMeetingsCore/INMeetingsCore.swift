import Foundation

/// Shared, testable core for the IN-meetings menu-bar app.
///
/// Capture (P2), detection (P3), the job bridge, and the SQLite store will land here as
/// modules the app target links. For the Slice-1 skeleton this just carries a version
/// string the menu bar renders, proving the app↔core link is wired end to end.
public enum INMeetingsCore {
    /// Semantic version of the core library.
    public static let version = "0.1.0"
}
