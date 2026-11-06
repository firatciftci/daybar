import SwiftUI

struct UpNextView: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather

    var body: some View {
        let now = model.now
        let live = store.occurrences(on: now).filter { $0.isLive(at: now) && !$0.isDeclined }
        let upcoming = store.nextOccurrences(after: now, limit: 8).filter { !$0.isDeclined }
        let reminders = store.reminders(on: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if live.isEmpty {
                    FreeHero(now: now, next: upcoming.first)
                } else {
                    ForEach(live) { occurrence in
                        LiveCard(occurrence: occurrence, now: now)
                    }
                }
                if let forecast = weather.forecast(for: now) {
                    HStack(spacing: 8) {
                        WeatherBadge(forecast: forecast)
                        Text(forecast.condition)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        if let place = weather.placeName {
                            Text(place)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                if !upcoming.isEmpty {
                    SectionTitle(L.upNext)
                    VStack(spacing: 1) {
                        ForEach(upcoming) { occurrence in
                            UpcomingRow(occurrence: occurrence, now: now)
                        }
                    }
                }
                if !reminders.isEmpty {
                    SectionTitle(L.reminders)
                    VStack(spacing: 1) {
                        ForEach(reminders) { item in
                            ReminderRow(item: item)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FreeHero: View {
    let now: Date
    let next: Occurrence?

    var body: some View {
        let headline: String = {
            guard let next, next.start.isSameDay(as: now) else { return L.freeRestOfDay }
            return L.freeUntil(Fmt.time(next.start))
        }()
        VStack(alignment: .leading, spacing: 6) {
            Text(L.now)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let next, next.start.isSameDay(as: now) {
                Text(L.startsIn(Fmt.duration(next.start.timeIntervalSince(now))))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

private struct LiveCard: View {
    let occurrence: Occurrence
    let now: Date
    @Environment(PanelModel.self) private var model

    var body: some View {
        let remaining = occurrence.end.timeIntervalSince(now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                CalendarDot(color: occurrence.color, size: 7)
                Text(L.liveNow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(occurrence.color.mix(with: .primary, by: 0.3))
                Spacer()
                Text(Fmt.timeRange(occurrence.start, occurrence.end))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(occurrence.title)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(3)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: occurrence.progress(at: now))
                    .tint(occurrence.color)
                    .accessibilityLabel(L.endsIn(Fmt.duration(remaining)))
                Text(L.endsIn(Fmt.duration(remaining)))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(countsDown: true))
            }
            if let meeting = occurrence.meeting {
                Button {
                    meeting.join()
                } label: {
                    Label {
                        Text(L.joinService(meeting.service.name))
                    } icon: {
                        MeetingGlyph(service: meeting.service, size: 14)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(occurrence.color.opacity(0.12)), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityAddTraits(.isButton)
        .onTapGesture { model.show(occurrence) }
        .contextMenu { EventContextMenu(occurrence: occurrence) }
    }
}

private struct UpcomingRow: View {
    let occurrence: Occurrence
    let now: Date
    @Environment(PanelModel.self) private var model

    var body: some View {
        let lead = occurrence.start.timeIntervalSince(now)
        let joinable = occurrence.meeting != nil && lead < 15 * 60
        ZStack(alignment: .trailing) {
            Button {
                model.show(occurrence)
            } label: {
                row(lead: lead, joinable: joinable)
            }
            .buttonStyle(RowButtonStyle())
            .contextMenu { EventContextMenu(occurrence: occurrence) }
            if joinable, let meeting = occurrence.meeting {
                JoinButton(meeting: meeting)
                    .padding(.trailing, 8)
            }
        }
    }

    private func row(lead: TimeInterval, joinable: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(occurrence.color)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(
                    occurrence.start.isSameDay(as: now)
                        ? Fmt.timeRange(occurrence.start, occurrence.end)
                        : "\(Fmt.compactDay(occurrence.start)), \(Fmt.time(occurrence.start))"
                )
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: joinable ? 70 : 4)
            if !joinable, lead < 12 * 3_600 {
                Text(Fmt.duration(lead))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.primary.opacity(0.07), in: .capsule)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
    }
}
