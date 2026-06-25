import CoreAudio
import Foundation

/// A selectable microphone input device. Carries the CoreAudio `AudioDeviceID` so the recorder can set it
/// on `AVAudioEngine.inputNode`, and the persistent `uid` (stable across reboots / re-plugs) so a saved
/// preference survives where the numeric id does not.
public struct AudioInputDevice: Sendable, Identifiable, Equatable {
    public let uid: String
    public let name: String
    public let id: AudioDeviceID

    public init(uid: String, name: String, id: AudioDeviceID) {
        self.uid = uid
        self.name = name
        self.id = id
    }
}

/// The raw per-device reads the enumerator needs — behind a protocol so the list-building/filtering logic
/// is unit-testable with synthetic data, with the real CoreAudio AudioObject calls living in
/// `CoreAudioPropertySource`.
protocol AudioPropertySource {
    /// Every `AudioDeviceID` the hardware exposes (`kAudioHardwarePropertyDevices`).
    func allDeviceIDs() -> [AudioDeviceID]
    /// The system default input device, or nil if none (`kAudioHardwarePropertyDefaultInputDevice`).
    func defaultInputDeviceID() -> AudioDeviceID?
    /// Input-scope channel count (`kAudioDevicePropertyStreamConfiguration`); 0 → output-only.
    func inputChannelCount(of device: AudioDeviceID) -> Int
    /// Persistent device UID (`kAudioDevicePropertyDeviceUID`).
    func uid(of device: AudioDeviceID) -> String?
    /// Human-readable name (`kAudioObjectPropertyName`).
    func name(of device: AudioDeviceID) -> String?
}

/// Lists the microphone input devices the user can choose between (decision 1: CoreAudio AudioObject API,
/// not `AVCaptureDevice`, because we need the `AudioDeviceID` to set the device on `AVAudioEngine`).
public struct AudioInputDeviceEnumerator {
    private let source: AudioPropertySource

    /// Production: real CoreAudio reads.
    public init() { self.source = CoreAudioPropertySource() }

    /// Test seam: inject a synthetic property source.
    init(source: AudioPropertySource) { self.source = source }

    /// Input-capable devices, in hardware order, keeping only those that have input streams and a readable
    /// UID + name.
    public func available() -> [AudioInputDevice] {
        source.allDeviceIDs().compactMap { id -> AudioInputDevice? in
            guard source.inputChannelCount(of: id) > 0,
                  let uid = source.uid(of: id),
                  let name = source.name(of: id) else { return nil }
            return AudioInputDevice(uid: uid, name: name, id: id)
        }
    }

    /// UID of the current system default input, or nil.
    public func defaultInputUID() -> String? {
        source.defaultInputDeviceID().flatMap(source.uid(of:))
    }
}

/// Real CoreAudio AudioObject property reads. Reads the global `AudioObjectID` system object for the device
/// list + default input, and per-device properties for stream config / UID / name.
struct CoreAudioPropertySource: AudioPropertySource {
    func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != 0 else { return nil }
        return device
    }

    func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    func uid(of device: AudioDeviceID) -> String? {
        string(device, selector: kAudioDevicePropertyDeviceUID)
    }

    func name(of device: AudioDeviceID) -> String? {
        string(device, selector: kAudioObjectPropertyName)
    }

    /// Read a `CFString` device property as a Swift `String`.
    private func string(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value as String
    }
}
