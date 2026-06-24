// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: tabbed Settings rebuilt for our detection/model/Drive state; English chrome.
import SwiftUI
import INMeetingsCore

struct AppSettingsView: View {
    var settings: MeetingDetectionSettings
    var models: ModelManager
    var vadModels: ModelManager
    var drive: DriveAuth
    var capture: CaptureSettings
    var audio: AudioDeviceSettings
    var recipeSettings: SummaryRecipeSettings
    var recipeRegistry: SummaryRecipeRegistry
    var body: some View {
        TabView {
            RecordingSettingsTab(settings: settings, capture: capture)
                .tabItem { Label("Recording", systemImage: "phone") }
            AudioSettingsTab(audio: audio).tabItem { Label("Audio", systemImage: "mic") }
            SummarySettingsTab(recipeSettings: recipeSettings, capture: capture, registry: recipeRegistry)
                .tabItem { Label("Summary", systemImage: "text.append") }
            ModelSettingsTab(model: models, vad: vadModels).tabItem { Label("Model", systemImage: "cube.box") }
            DriveSettingsTab(drive: drive).tabItem { Label("Drive", systemImage: "externaldrive") }
        }
        .frame(width: 540, height: 480).padding(20)
    }
}
