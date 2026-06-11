import CoreAudio
import Foundation

/// One process's audio I/O state, as reported by Core Audio (ADR-001 / prototype P3).
struct AudioProc: Equatable {
    let bundleID: String
    let input: Bool   // capturing the mic
    let output: Bool  // playing to a device

    /// Both directions active → a live call (vs. one-way playback or dictation).
    var bidirectional: Bool { input && output }
    var app: String { AudioProcessProbe.normalizedApp(bundleID) }
}

/// Reads per-process audio I/O from Core Audio.
///
/// The robust, app-agnostic mechanism real call-recorders use: ask Core Audio which processes are
/// doing audio I/O, and treat a process with BOTH input (mic) AND output (speaker) active as a live
/// call. Bidirectional audio distinguishes a call (Zoom / Chrome-Meet / WhatsApp / Teams / FaceTime)
/// from one-way playback (YouTube = output only) or dictation (voice memo = input only). The process
/// object carries its own bundle ID, so we learn WHICH app with no per-app special-casing, no
/// Accessibility, and no Automation permission. Detection needs **no TCC grant** — capture (ADR-002)
/// is what requires the audio-recording permission. Verified live in prototype P3.
///
/// API (macOS 14.2+): `kAudioHardwarePropertyProcessObjectList` →
/// per process `kAudioProcessPropertyBundleID`, `…IsRunningInput` / `…IsRunningOutput`.
enum AudioProcessProbe {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Audio shows up under helper/child bundle IDs (e.g. `com.google.Chrome.helper`); normalize to the
    /// real app and give the common meeting apps a friendly name for the context assembler.
    static let friendlyNames: [String: String] = [
        "com.google.Chrome": "Google Chrome (Meet/web call)",
        "com.apple.Safari": "Safari (web call)",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack (huddle)",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.apple.FaceTime": "FaceTime",
    ]

    /// Strip Chromium/Electron helper suffixes then apply a friendly name:
    /// `"com.google.Chrome.helper (Renderer)"` → `"Google Chrome (Meet/web call)"`.
    static func normalizedApp(_ bundleID: String) -> String {
        var id = bundleID
        for marker in [".helper", ".Helper"] {
            if let r = id.range(of: marker) { id = String(id[..<r.lowerBound]); break }
        }
        return friendlyNames[id] ?? id
    }

    /// Processes currently doing audio I/O (idle processes filtered out).
    @available(macOS 14.2, *)
    static func audioProcesses() -> [AudioProc] {
        processObjectList().compactMap { id in
            let bundle = readString(id, kAudioProcessPropertyBundleID) ?? "(unknown)"
            let inRun = readUInt32(id, kAudioProcessPropertyIsRunningInput) != 0
            let outRun = readUInt32(id, kAudioProcessPropertyIsRunningOutput) != 0
            guard inRun || outRun else { return nil }
            return AudioProc(bundleID: bundle, input: inRun, output: outRun)
        }
    }

    // MARK: - Core Audio property helpers

    private static func processObjectList() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown),
                                  count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func readUInt32(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var val: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(objID, &addr, 0, nil, &size, &val)
        return val
    }

    private static func readString(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objID, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var cfStr: CFString = "" as CFString
        let err = withUnsafeMutablePointer(to: &cfStr) {
            AudioObjectGetPropertyData(objID, &addr, 0, nil, &size, $0)
        }
        return err == noErr ? (cfStr as String) : nil
    }
}
