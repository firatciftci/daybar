import EventKit
import SwiftUI

struct ProgressBar: View {
    let color: Color
    let progress: Double
    var outlined = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if outlined {
                    Capsule()
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
                } else {
                    Capsule().fill(color.opacity(progress > 0 && progress < 1 ? 0.3 : 1))
                    if progress > 0, progress < 1 {
                        Capsule()
                            .fill(color)
                            .frame(height: max(proxy.size.width, proxy.size.height * progress))
                    }
                }
            }
        }
    }
}

struct JoinButton: View {
    let meeting: MeetingLink
    var prominent = false

    var body: some View {
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button {
            meeting.join()
        } label: {
            Label {
                Text(L.join)
            } icon: {
                MeetingGlyph(service: meeting.service, size: 11)
            }
            .font(.system(size: 11.5, weight: .semibold))
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .help(L.joinService(meeting.service.name))
    }
}

struct EventContextMenu: View {
    let occurrence: Occurrence
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store

    var body: some View {
        Button(L.showEvent, systemImage: "info.circle") { model.show(occurrence) }
        if let meeting = occurrence.meeting {
            Button(L.joinService(meeting.service.name), systemImage: "video") { meeting.join() }
            Button(L.copyLink, systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meeting.url.absoluteString, forType: .string)
            }
        }
        Divider()
        let editable = store.event(for: occurrence)?.calendar?.allowsContentModifications == true
        if editable, occurrence.birthday == nil {
            Button(L.edit, systemImage: "pencil") { model.edit(occurrence) }
        }
        Button(L.duplicate, systemImage: "plus.square.on.square") { _ = store.duplicate(occurrence) }
        Button(L.openInCalendar, systemImage: "calendar") { store.openInCalendar(occurrence) }
        if editable {
            Divider()
            Button(L.deleteEvent, systemImage: "trash", role: .destructive) {
                model.deleteRequest = occurrence
            }
        }
    }
}

struct WeatherCreditView: View {
    let credit: WeatherCredit
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            if let mark = scheme == .dark ? credit.darkMark : credit.lightMark {
                AsyncImage(url: mark) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(height: 11)
            }
            Link(credit.label, destination: credit.legalPage)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
