import Foundation

/// Per-user persistence of the chosen backup location (ADR-006). Plain `UserDefaults` — the location
/// (drive + folder ids) isn't secret; only the OAuth tokens are (those live in the Keychain).
public final class DriveLocationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "drive.backupLocation"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> DriveLocation? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DriveLocation.self, from: data)
    }

    public func save(_ location: DriveLocation) {
        defaults.set(try? JSONEncoder().encode(location), forKey: key)
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
