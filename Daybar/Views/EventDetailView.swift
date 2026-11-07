import EventKit
import MapKit
import SwiftUI

struct EventDetailView: View {
    let occurrence: Occurrence
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs
    @State private var event: EKEvent?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var notesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let birthday = occurrence.birthday {
                    BirthdayHero(occurrence: occurrence, birthday: birthday)
                } else {
                    header
                }
                if let meeting = occurrence.meeting, occurrence.end > model.now {
                    JoinWideButton(meeting: meeting)
                }
                if let location = occurrence.location {
                    locationBlock(location)
                }
                if let event, let attendees = event.attendees, !attendees.isEmpty {
                    attendeesBlock(attendees, organizer: event.organizer)
                }
                if let notes = event?.notes.map(\.plainNotes), !notes.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(linkified(notes))
                                .font(.system(size: 12.5))
                                .textSelection(.enabled)
                                .lineLimit(notesExpanded ? nil : 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if notes.count > 320 || notes.filter(\.isNewline).count > 7 {
                                Button(notesExpanded ? L.showLess : L.showMore) {
                                    withAnimation(.smooth(duration: 0.3)) { notesExpanded.toggle() }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                if occurrence.birthday == nil, let url = event?.url, url != occurrence.meeting?.url, url.scheme?.hasPrefix("http") == true {
                    DetailCard {
                        Link(destination: url) {
                            Label(url.host() ?? url.absoluteString, systemImage: "link")
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task(id: occurrence.id) {
            event = store.event(for: occurrence)
            await resolveCoordinate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CalendarDot(color: occurrence.color, size: 8)
                Text(occurrence.calendarTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(occurrence.title)
                .font(.system(size: 20, weight: .bold))
                .strikethrough(occurrence.isDeclined)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.longDay(occurrence.start))
                    .font(.system(size: 13, weight: .medium))
                Text(timeText(in: .autoupdatingCurrent))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                if let zone = prefs.secondTimeZone, !occurrence.isAllDay {
                    Text("\(Fmt.zoneName(zone)) \(timeText(in: zone))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let event, let summary = RepeatRule.summary(of: event) {
                    Label(summary, systemImage: "repeat")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let event {
                    ForEach(AlertOffset.relative(event.alarms).map(AlertOffset.minutes), id: \.self) { minutes in
                        Label(AlertOffset.title(minutes, allDay: event.isAllDay), systemImage: "bell")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeText(in zone: TimeZone) -> String {
        if occurrence.isAllDay {
            let last = occurrence.end.addingTimeInterval(-1)
            return occurrence.start.isSameDay(as: last) ? L.allDay : "\(L.allDay), \(Fmt.gapRange(occurrence.start, last))"
        }
        if occurrence.spansMultipleDays {
            var style = Date.IntervalFormatStyle(date: .abbreviated, time: .shortened)
            style.timeZone = zone
            return (occurrence.start..<occurrence.end).formatted(style)
        }
        return "\(Fmt.timeRange(occurrence.start, occurrence.end, in: zone)), \(Fmt.duration(occurrence.duration))"
    }

    private func locationBlock(_ location: String) -> some View {
        DetailCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let coordinate {
                    Map(
                        initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900)),
                        interactionModes: []
                    ) {
                        Marker(occurrence.title, coordinate: coordinate)
                            .tint(occurrence.color)
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 120)
                    .allowsHitTesting(false)
                }
                Button {
                    openInMaps(location)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .accessibilityHidden(true)
                            .foregroundStyle(.secondary)
                        Text(location)
                            .font(.system(size: 12.5))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .accessibilityHidden(true)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func attendeesBlock(_ attendees: Array<EKParticipant>, organizer: EKParticipant?) -> some View {
        DetailCard(padding: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.attendees)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                ForEach(Array(attendees.enumerated()), id: \.offset) { _, participant in
                    AttendeeRow(
                        participant: participant, isOrganizer: participant.url == organizer?.url,
                        statusText: statusText(participant.participantStatus))
                }
                if occurrence.isPendingInvite {
                    Button(L.respondInCalendar) { store.openInCalendar(occurrence) }
                        .buttonStyle(.glass)
                        .padding(6)
                }
            }
        }
    }

    private func statusText(_ status: EKParticipantStatus) -> String {
        switch status {
        case .accepted: L.accepted
        case .declined: L.declined
        case .tentative: L.maybe
        default: L.awaitingResponse
        }
    }

    private func resolveCoordinate() async {
        if let geo = event?.structuredLocation?.geoLocation {
            coordinate = geo.coordinate
            return
        }
        guard let location = occurrence.location, let request = MKGeocodingRequest(addressString: location) else { return }
        if let item = try? await request.mapItems.first {
            coordinate = item.location.coordinate
        }
    }

    private func openInMaps(_ location: String) {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                let lower = AttributedString.Index(range.lowerBound, within: attributed),
                let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].link = url
        }
        return attributed
    }
}

private struct AttendeeRow: View {
    let participant: EKParticipant
    let isOrganizer: Bool
    let statusText: String
    @Environment(ContactsModel.self) private var contacts

    var body: some View {
        let email = participant.url.absoluteString.hasPrefix("mailto:") ? String(participant.url.absoluteString.dropFirst(7)) : nil
        let named = participant.name.flatMap { $0.contains("@") ? nil : $0 }
        let card = contacts.card(for: participant, email: email, name: named)
        let given = named ?? card?.name
        let name = given ?? email ?? participant.url.absoluteString
        Button {
            if let url = card?.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 9) {
                ContactAvatar(card: card, name: name, size: 24)
                    .overlay(alignment: .bottomTrailing) {
                        badge
                            .offset(x: 3, y: 2)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 12.5))
                    if given != nil, let email {
                        Text(email)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if isOrganizer || participant.isCurrentUser {
                    Text(isOrganizer ? L.organizer : statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 9))
        .disabled(card == nil)
        .help(card == nil ? statusText : "\(statusText). \(L.showContact)")
    }

    private var badge: some View {
        let (symbol, color): (String, Color) =
            switch participant.participantStatus {
            case .accepted: ("checkmark.circle.fill", .green)
            case .declined: ("xmark.circle.fill", .red)
            case .tentative: ("questionmark.circle.fill", .orange)
            default: ("clock.fill", .gray)
            }
        return Image(systemName: symbol)
            .accessibilityHidden(true)
            .font(.system(size: 10, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .background(Circle().fill(.background).padding(-1.5))
    }
}

private struct BirthdayHero: View {
    let occurrence: Occurrence
    let birthday: Birthday
    @Environment(ContactsModel.self) private var contacts
    @State private var celebrations = 0

    var body: some View {
        let today = occurrence.start.isToday
        VStack(spacing: 6) {
            let card = contacts.card(forBirthday: birthday)
            Button {
                celebrations += 1
            } label: {
                ContactAvatar(card: card, name: birthday.name, size: 92)
                    .padding(4)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .overlay(alignment: .bottomTrailing) {
                        BirthdayGlyph(size: 17, bounce: celebrations)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular, in: .circle)
                            .offset(x: 4, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .accessibilityLabel(L.birthday)
            Text(birthday.name)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text(birthday.ageLine(on: occurrence.start))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Party.accent)
            Text(Fmt.relativeDayName(occurrence.start).map { "\($0), \(Fmt.longDay(occurrence.start))" } ?? Fmt.longDay(occurrence.start))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            if let url = card?.url ?? birthday.contactURL {
                Button(L.showContact, systemImage: "person.crop.circle") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .padding(.horizontal, 16)
        .background {
            SprinkleField()
                .mask {
                    RadialGradient(colors: [.clear, .black], center: .center, startRadius: 70, endRadius: 210)
                }
        }
        .background(.primary.opacity(0.05))
        .overlay { ConfettiBurst(trigger: celebrations) }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .task {
            guard today else { return }
            try? await Task.sleep(for: .milliseconds(280))
            celebrations += 1
        }
    }
}

struct DetailCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: .rect(cornerRadius: 14, style: .continuous))
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }
}

private struct JoinWideButton: View {
    let meeting: MeetingLink

    var body: some View {
        Button {
            meeting.join()
        } label: {
            Label {
                Text(L.joinService(meeting.service.name))
            } icon: {
                MeetingGlyph(service: meeting.service, size: 15)
            }
            .font(.system(size: 13.5, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .keyboardShortcut(.return, modifiers: .command)
    }
}
