import SwiftUI

/// A simple horizontal VU bar: maps dBFS (−60…0) to a 0…1 fill with a green→yellow→red tint, so a glance
/// tells you the input is live and not clipping. Shared by the Audio settings live meter and the recording
/// HUD's per-track meters.
struct LevelBar: View {
    /// Current level in dBFS (−120 when silent).
    let db: Float

    private var fraction: Double {
        let clamped = min(max(Double(db), -60), 0)   // useful range: −60…0 dBFS
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
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.1), value: fraction)
            }
        }
        .frame(height: 10)
    }
}
