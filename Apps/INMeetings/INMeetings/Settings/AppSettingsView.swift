// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: tabbed Settings rebuilt for our detection/model/Drive state; English chrome.
import SwiftUI
struct AppSettingsView: View {
    var settings: MeetingDetectionSettings
    var models: ModelManager
    var vadModels: ModelManager
    var drive: DriveAuth
    var body: some View {
        TabView {
            RecordingSettingsTab(settings: settings).tabItem { Label("Recording", systemImage: "phone") }
            ModelSettingsTab(model: models, vad: vadModels).tabItem { Label("Model", systemImage: "cube.box") }
            DriveSettingsTab(drive: drive).tabItem { Label("Drive", systemImage: "externaldrive") }
        }
        .frame(width: 540, height: 460).padding(20)
    }
}
