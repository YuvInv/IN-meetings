import Foundation
import ServiceManagement

/// Abstraction over login-item registration so the toggle logic can be unit-tested with a fake.
public protocol LaunchAtLoginManaging: AnyObject {
    /// Whether the app is currently registered to launch at login.
    var isEnabled: Bool { get }
    /// Register (`true`) or unregister (`false`) the app as a login item.
    func setEnabled(_ enabled: Bool) throws
}

/// Concrete implementation backed by `SMAppService.mainApp` (macOS 13+).
///
/// On a dev/DerivedData run this registers whatever bundle is currently running — that is expected
/// behaviour. The setting only fully matters post-install (Developer-ID / notarized .dmg).
public final class SystemLaunchAtLogin: LaunchAtLoginManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Throws an `SMAppServiceError` if the system call fails.
    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Helper that builds a human-readable version string from a bundle.
///
///     versionString(bundle: .main)   // → "Version 0.1.0 (1)"
public func versionString(bundle: Bundle = .main) -> String {
    let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "Version \(short) (\(build))"
}
