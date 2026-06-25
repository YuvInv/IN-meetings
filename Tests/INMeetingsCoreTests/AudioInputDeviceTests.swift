import CoreAudio
import XCTest
@testable import INMeetingsCore

final class AudioInputDeviceTests: XCTestCase {
    /// Only devices that expose input channels survive enumeration; output-only devices are dropped.
    func testKeepsOnlyInputDevices() {
        let source = StubAudioPropertySource(
            deviceIDs: [10, 20, 30],
            defaultInputID: 20,
            devices: [
                10: .init(uid: "mic-uid", name: "Built-in Mic", inputChannels: 1),
                20: .init(uid: "iface-uid", name: "USB Interface", inputChannels: 2),
                30: .init(uid: "speakers-uid", name: "External Speakers", inputChannels: 0), // output-only
            ])
        let enumerator = AudioInputDeviceEnumerator(source: source)

        let available = enumerator.available()
        XCTAssertEqual(available.map(\.uid), ["mic-uid", "iface-uid"])
        XCTAssertEqual(available.map(\.name), ["Built-in Mic", "USB Interface"])
        XCTAssertEqual(available.first?.id, 10)
    }

    func testDefaultInputUID() {
        let source = StubAudioPropertySource(
            deviceIDs: [10, 20],
            defaultInputID: 20,
            devices: [
                10: .init(uid: "mic-uid", name: "Built-in Mic", inputChannels: 1),
                20: .init(uid: "iface-uid", name: "USB Interface", inputChannels: 2),
            ])
        let enumerator = AudioInputDeviceEnumerator(source: source)
        XCTAssertEqual(enumerator.defaultInputUID(), "iface-uid")
    }

    func testDefaultInputUIDIsNilWhenNoDefault() {
        let source = StubAudioPropertySource(
            deviceIDs: [10],
            defaultInputID: nil,
            devices: [10: .init(uid: "mic-uid", name: "Built-in Mic", inputChannels: 1)])
        let enumerator = AudioInputDeviceEnumerator(source: source)
        XCTAssertNil(enumerator.defaultInputUID())
    }

    func testEmptyHardwareYieldsNoDevices() {
        let source = StubAudioPropertySource(deviceIDs: [], defaultInputID: nil, devices: [:])
        let enumerator = AudioInputDeviceEnumerator(source: source)
        XCTAssertTrue(enumerator.available().isEmpty)
    }
}

/// In-memory stand-in for the CoreAudio property reads so the list-building/filtering logic is testable
/// without real hardware.
private struct StubAudioPropertySource: AudioPropertySource {
    struct Device { let uid: String; let name: String; let inputChannels: Int }

    let deviceIDs: [AudioDeviceID]
    let defaultInputID: AudioDeviceID?
    let devices: [AudioDeviceID: Device]

    func allDeviceIDs() -> [AudioDeviceID] { deviceIDs }
    func defaultInputDeviceID() -> AudioDeviceID? { defaultInputID }
    func inputChannelCount(of device: AudioDeviceID) -> Int { devices[device]?.inputChannels ?? 0 }
    func uid(of device: AudioDeviceID) -> String? { devices[device]?.uid }
    func name(of device: AudioDeviceID) -> String? { devices[device]?.name }
}
