// P3 — meeting detection prototype (ADR-001).
//
// Validates the MULTI-SIGNAL detector: a meeting is "live" when a meeting app is
// running/frontmost AND (mic is in use OR a meeting URL is the active browser tab).
// Mic-in-use alone is unreliable (AirPods always report false — Apple bug), so we fuse signals.
//
// Signals:
//   1. Frontmost + running apps        — NSWorkspace (no permission)
//   2. Mic in use                      — CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere
//                                        on the default input device (no permission; false for Bluetooth)
//   3. Active browser tab URL          — AppleScript (Automation TCC; prompts on first use)
//
// Run:  swift run p3-detect        (polls every 2s; Ctrl-C to stop)
// First run will prompt for Automation permission for Chrome/Safari when a browser is frontmost.

import AppKit
import CoreAudio
import Foundation

// MARK: - Known meeting apps & URL patterns

let meetingBundleIDs: Set<String> = [
    "us.zoom.xos",                 // Zoom
    "com.microsoft.teams2",        // Teams (new)
    "com.microsoft.teams",         // Teams (classic)
    "com.tinyspeck.slackmacgap",   // Slack (huddles)
    "Cisco-Systems.Spark",         // Webex
]
let browserBundleIDs: Set<String> = [
    "com.google.Chrome",
    "com.apple.Safari",
    "company.thebrowser.Browser",  // Arc
    "com.brave.Browser",
    "com.microsoft.edgemac",
]
let meetingURLNeedles = ["meet.google.com", "zoom.us/j/", "zoom.us/wc/", "teams.microsoft.com",
                         "teams.live.com", "webex.com/meet", "whereby.com"]

// MARK: - Signal 1: apps

func runningMeetingApps() -> [String] {
    NSWorkspace.shared.runningApplications.compactMap { app in
        guard let id = app.bundleIdentifier, meetingBundleIDs.contains(id) else { return nil }
        return app.localizedName ?? id
    }
}

func frontmostBundleID() -> String? {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
}

// MARK: - Signal 2: mic in use (CoreAudio)

func defaultInputDeviceID() -> AudioObjectID? {
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
    return status == noErr ? deviceID : nil
}

func micInUse() -> Bool {
    guard let dev = defaultInputDeviceID() else { return false }
    var inUse: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &inUse)
    return status == noErr && inUse != 0
}

// MARK: - Signal 3: active browser tab URL (AppleScript / Automation TCC)

func activeTabURL(forBundleID id: String) -> String? {
    let script: String
    switch id {
    case "com.apple.Safari":
        script = "tell application \"Safari\" to return URL of front document"
    case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser":
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Google Chrome"
        script = "tell application \"\(appName)\" to return URL of active tab of front window"
    default:
        return nil
    }
    var error: NSDictionary?
    guard let s = NSAppleScript(source: script) else { return nil }
    let result = s.executeAndReturnError(&error)
    if let error { fputs("  (AppleScript error: \(error[NSAppleScript.errorMessage] ?? "?") — grant Automation permission)\n", stderr) ; return nil }
    return result.stringValue
}

// MARK: - Fused verdict

func meetingURLActive() -> (Bool, String?) {
    guard let front = frontmostBundleID(), browserBundleIDs.contains(front) else { return (false, nil) }
    guard let url = activeTabURL(forBundleID: front) else { return (false, nil) }
    let hit = meetingURLNeedles.first { url.contains($0) }
    return (hit != nil, hit != nil ? url : nil)
}

func evaluate() {
    let apps = runningMeetingApps()
    let front = frontmostBundleID() ?? "?"
    let mic = micInUse()
    let (urlHit, url) = meetingURLActive()

    // Arming policy (ADR-001): (meeting app present AND (mic OR meeting URL)) OR meeting URL active.
    let appPresent = !apps.isEmpty || browserBundleIDs.contains(front)
    let armed = (appPresent && (mic || urlHit)) || urlHit

    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] armed=\(armed ? "YES" : "no ") | meetingApps=\(apps) front=\(front) mic=\(mic) urlHit=\(urlHit)\(url != nil ? " (\(url!))" : "")")
}

// MARK: - Loop

print("P3 detector — polling every 2s. Ctrl-C to stop.")
print("Signals: NSWorkspace apps · CoreAudio mic-in-use · AppleScript tab URL (Automation TCC).")
print(String(repeating: "-", count: 80))
while true {
    evaluate()
    Thread.sleep(forTimeInterval: 2.0)
}
