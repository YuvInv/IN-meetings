import SwiftUI
import INMeetingsCore

/// Settings → Audio: choose the microphone input device, watch a live input-level (VU) meter, and
/// optionally enable adaptive gain (auto-boost a quiet mic). Bound to `AudioDeviceSettings` (persisted via
/// UserDefaults). The VU meter runs a short-lived `InputLevelMonitor` while this tab is on screen and
/// re-points it when the device selection changes.
struct AudioSettingsTab: View {
    var audio: AudioDeviceSettings

    @State private var monitor = InputLevelMonitor()
    @State private var devices: [AudioInputDevice] = []

    /// `Picker` can't bind a `nil` tag directly, so map nil ⇄ "" (the System Default sentinel).
    private var selection: Binding<String> {
        Binding(
            get: { audio.selectedInputDeviceUID ?? "" },
            set: { audio.selectedInputDeviceUID = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Audio")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Picker("Input device", selection: selection) {
                    Text("System Default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Text("Which microphone to record from. “System Default” follows your macOS sound input. An unplugged device falls back to the default automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Input level")
                    .font(.subheadline.weight(.medium))
                LevelBar(db: monitor.currentDB)
                Text("Live level from the selected mic — speak to check it moves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Adaptive gain", isOn: Binding(
                    get: { audio.adaptiveGainEnabled },
                    set: { audio.adaptiveGainEnabled = $0 }))
                Text("Auto-boosts a quiet mic toward a target level while recording. Off by default — the raw mic track is the source of truth for transcription, so it’s left untouched unless you opt in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if audio.adaptiveGainEnabled {
                    HStack(spacing: 8) {
                        Text("Target level")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { audio.targetInputLevelDBFS },
                            set: { audio.targetInputLevelDBFS = $0 }), in: -30 ... -6)
                        Text("\(Int(audio.targetInputLevelDBFS)) dB")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            devices = AudioInputDeviceEnumerator().available()
            monitor.start(deviceUID: audio.resolvedDeviceUID(available: devices))
        }
        .onDisappear { monitor.stop() }
        .onChange(of: audio.selectedInputDeviceUID) { _, _ in
            // Re-point the live meter (and refresh the list, in case a device was just plugged in).
            devices = AudioInputDeviceEnumerator().available()
            monitor.start(deviceUID: audio.resolvedDeviceUID(available: devices))
        }
    }
}

/// A simple horizontal VU bar: maps dBFS (−60…0) to a 0…1 fill with a green→yellow→red tint, so a glance
/// tells you the mic is live and not clipping.
private struct LevelBar: View {
    /// Current level in dBFS (−120 when silent).
    let db: Float

    private var fraction: Double {
        // Clamp the useful range to −60…0 dBFS.
        let clamped = min(max(Double(db), -60), 0)
        return (clamped + 60) / 60
    }

    private var tint: Color {
        if db > -6 { return .red }
        if db > -18 { return .yellow }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.1), value: fraction)
            }
        }
        .frame(height: 10)
    }
}
