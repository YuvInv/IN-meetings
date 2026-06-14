import Foundation

/// Where a user backs up their meetings — chosen at runtime after connecting their account, persisted
/// per user (ADR-006). Not hardcoded: each teammate picks their own Shared Drive / folder.
public struct DriveLocation: Codable, Sendable, Equatable {
    /// The Shared Drive id (nil = the user's My Drive). Scopes Drive API calls to that drive.
    public let driveID: String?
    /// The base folder under which the app creates `<Company>/<meeting>/` subfolders.
    public let folderID: String
    /// Human label for the UI, e.g. "IN Meetings (Shared Drive)".
    public let displayName: String

    public init(driveID: String?, folderID: String, displayName: String) {
        self.driveID = driveID
        self.folderID = folderID
        self.displayName = displayName
    }
}
