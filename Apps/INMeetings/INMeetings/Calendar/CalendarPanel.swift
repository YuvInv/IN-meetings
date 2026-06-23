import SwiftUI
import Combine
import INMeetingsCore

/// The dashboard's right-side day-agenda inspector. Pick an event → upload a recording bound to it, or
/// upload without an event from the footer. Gated on Google being connected.
struct CalendarPanel: View {
    let drive: DriveAuth
    @Bindable var model: CalendarPanelModel
    /// Called when the user chooses to upload for a specific event (nil = no-event footer).
    let onUpload: (CalendarEvent?) -> Void
    /// Called when the user taps an already-recorded event to open it.
    let onOpenRecorded: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if drive.isConnected {
                header   // pinned at the top — the content below fills the rest so it never shifts
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                disconnected
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            // Always available — a no-event import has no Google dependency, so it must work even when
            // the calendar (and the agenda above) is disconnected.
            Button { onUpload(nil) } label: {
                Label("Upload recording without an event…", systemImage: "waveform.badge.plus")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(minWidth: 280, maxHeight: .infinity, alignment: .top)
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .jobBridgeDidFinish)) { _ in
            // A finished import may have added a recording for a visible event — refresh the ✓ markers.
            Task { await model.load() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { Task { await model.step(days: -1) } } label: { Image(systemName: "chevron.left") }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedDay, format: .dateTime.weekday(.wide))
                    .font(.headline)
                Text(model.selectedDay, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { Task { await model.step(days: 1) } } label: { Image(systemName: "chevron.right") }
            Spacer()
            Button("Today") { Task { await model.goToToday() } }
                .buttonStyle(.borderless).font(.caption)
            Button { Task { await model.load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)   // centered; header stays put
        case .error(let message):
            VStack(spacing: 8) {
                ContentUnavailableView("Couldn't load calendar", systemImage: "calendar.badge.exclamationmark",
                                       description: Text(message))
                Button("Retry") { Task { await model.load(force: true) } }
            }.padding(12)
        case .loaded(let events):
            if events.isEmpty {
                ContentUnavailableView("No events", systemImage: "calendar",
                                       description: Text("Nothing scheduled this day.")).padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(events, id: \.id) { event in row(event) }
                    }.padding(8)
                }
            }
        }
    }

    @ViewBuilder private func row(_ event: CalendarEvent) -> some View {
        let recorded = model.isRecorded(event)
        let timeLabel = Self.timeLabel(event)   // nil for all-day events → no upload action (spec)
        VStack(alignment: .leading, spacing: 2) {
            Text(event.summary ?? "(no title)").font(.subheadline).lineLimit(1)
            HStack(spacing: 6) {
                Text(timeLabel ?? "All day").font(.caption).foregroundStyle(.secondary)
                if let n = event.attendees?.count, n > 0 {
                    Text("· \(n) attendee\(n == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if recorded {
                    Label("recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else if timeLabel != nil {
                    Button("Upload…") { onUpload(event) }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(recorded ? 0.4 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { if recorded { onOpenRecorded(event) } }
    }

    private var disconnected: some View {
        ContentUnavailableView {
            Label("Connect Google", systemImage: "calendar")
        } description: {
            Text("Connect your Google account to see your calendar and import recordings.")
        } actions: {
            Button("Connect Google…") { Task { await drive.connect() } }
        }
        .padding(12)
    }

    /// "10:00–10:30" for a timed event; nil for all-day (no time → not a recordable slot).
    static func timeLabel(_ event: CalendarEvent) -> String? {
        let iso = ISO8601DateFormatter()
        guard let s = event.start.dateTime.flatMap({ iso.date(from: $0) }),
              let e = event.end.dateTime.flatMap({ iso.date(from: $0) }) else { return nil }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(s.formatted(f))–\(e.formatted(f))"
    }
}
