// P3 — meeting detection via Core Audio process I/O (ADR-001).
//
// The robust, app-agnostic mechanism real call-recorders use: ask Core Audio which processes are
// doing audio I/O, and treat a process with BOTH input (mic) AND output (speaker) active as a live
// CALL. Bidirectional audio distinguishes a call (Zoom / Chrome-Meet / WhatsApp / Teams / FaceTime)
// from one-way playback (YouTube = output only) or dictation (voice memo = input only) — and the
// process object carries its own bundle ID, so we learn WHICH app with no per-app special-casing,
// no Accessibility, and no Automation permission.
//
// API (macOS 14.2+): kAudioHardwarePropertyProcessObjectList →
//   per process: kAudioProcessPropertyBundleID, kAudioProcessPropertyIsRunningInput / …Output.
//
// Run:  swift run p3-detect        (polls every 2s; Ctrl-C to stop)

import CoreAudio
import Foundation

// MARK: - Core Audio property helpers

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func processObjectList() -> [AudioObjectID] {
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

func readUInt32(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var addr = AudioObjectPropertyAddress(mSelector: selector,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var val: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(objID, &addr, 0, nil, &size, &val)
    return val
}

func readString(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
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

// MARK: - Per-process audio state

// Audio shows up under helper/child bundle IDs (e.g. com.google.Chrome.helper); normalize to the
// real app and give the common meeting apps a friendly name for the context assembler.
let friendlyNames: [String: String] = [
    "com.google.Chrome": "Google Chrome (Meet/web call)",
    "com.apple.Safari": "Safari (web call)",
    "us.zoom.xos": "Zoom",
    "com.microsoft.teams2": "Microsoft Teams",
    "com.microsoft.teams": "Microsoft Teams",
    "com.tinyspeck.slackmacgap": "Slack (huddle)",
    "net.whatsapp.WhatsApp": "WhatsApp",
    "com.apple.FaceTime": "FaceTime",
]

func normalizedApp(_ bundleID: String) -> String {
    // strip Chromium/Electron helper suffixes: "com.google.Chrome.helper (Renderer)" → "com.google.Chrome"
    var id = bundleID
    for marker in [".helper", ".Helper"] {
        if let r = id.range(of: marker) { id = String(id[..<r.lowerBound]); break }
    }
    return friendlyNames[id] ?? id
}

struct AudioProc {
    let bundleID: String
    let input: Bool   // capturing the mic
    let output: Bool  // playing to a device
    var bidirectional: Bool { input && output }   // → a live call
    var app: String { normalizedApp(bundleID) }
}

@available(macOS 14.2, *)
func audioProcesses() -> [AudioProc] {
    processObjectList().compactMap { id in
        let bundle = readString(id, kAudioProcessPropertyBundleID) ?? "(unknown)"
        let inRun = readUInt32(id, kAudioProcessPropertyIsRunningInput) != 0
        let outRun = readUInt32(id, kAudioProcessPropertyIsRunningOutput) != 0
        guard inRun || outRun else { return nil }   // ignore idle processes
        return AudioProc(bundleID: bundle, input: inRun, output: outRun)
    }
}

// MARK: - Verdict

@available(macOS 14.2, *)
func evaluate() {
    let procs = audioProcesses()
    let calls = procs.filter(\.bidirectional)
    let armed = !calls.isEmpty

    let ts = ISO8601DateFormatter().string(from: Date())
    if armed {
        let who = Set(calls.map(\.app)).sorted().joined(separator: ", ")
        print("[\(ts)] armed=YES  CALL in: \(who)")
    } else {
        let active = procs.map { "\($0.app)[\($0.input ? "in" : "")\($0.output ? "out" : "")]" }
        print("[\(ts)] armed=no   audio I/O: \(active.isEmpty ? "(none)" : active.joined(separator: " "))")
    }
}

// MARK: - Loop

setvbuf(stdout, nil, _IOLBF, 0)
if #available(macOS 14.2, *) {
    print("P3 detector — Core Audio process I/O. A process with BOTH input+output = a live call.")
    print("Polling every 2s. Ctrl-C to stop.")
    print(String(repeating: "-", count: 80))
    while true {
        evaluate()
        Thread.sleep(forTimeInterval: 2.0)
    }
} else {
    fputs("requires macOS 14.2+\n", stderr)
    exit(1)
}
