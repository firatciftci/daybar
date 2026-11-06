import SwiftUI

enum AgendaItem: Identifiable {
    case day(Date)
    case gap(Date, Date)

    var id: Date {
        switch self {
        case .day(let date): date
        case .gap(let start, _): start
        }
    }

    func contains(_ date: Date) -> Bool {
        switch self {
        case .day(let day): day.isSameDay(as: date)
        case let .gap(start, end): date >= start && date <= end
        }
    }
}

struct AgendaList: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather
    @Environment(\.metrics) private var metrics
    @State private var position = ScrollPosition(id: Date().startOfDay, anchor: .top)
    @State private var suppressSyncUntil = Date.distantPast
    @State private var userScrolling = false
    @State private var settle: Task<Void, Never>?
    @State private var visibleIDs: Array<Date> = []
    @State private var jumpOpacity: Double = 1
    @State private var jumpOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: Array<AgendaItem> {
        _ = store.revision
        var result: Array<AgendaItem> = []
        let today = Date().startOfDay
        var gapStart: Date?
        var cursor = store.range.start
        let end = store.range.end
        while cursor < end {
            let hasContent = !store.occurrences(on: cursor).isEmpty || !store.reminders(on: cursor).isEmpty
            if hasContent || cursor == today {
                if let start = gapStart {
                    result.append(.gap(start, cursor.adding(days: -1)))
                    gapStart = nil
                }
                result.append(.day(cursor))
            } else if gapStart == nil {
                gapStart = cursor
            }
            cursor = cursor.adding(days: 1)
        }
        if let start = gapStart {
            result.append(.gap(start, end.adding(days: -1)))
        }
        return result
    }

    var body: some View {
        let items = items
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case .day(let date):
                        VStack(alignment: .leading, spacing: 0) {
                            DayHeader(date: date, forecast: weather.forecast(for: date))
                            DaySectionContent(date: date)
                                .padding(.bottom, metrics.compact ? 2 : 8)
                        }
                        .id(date)
                    case let .gap(start, end):
                        GapRow(start: start, end: end)
                            .id(start)
                    }
                }
                if let credit = weather.credit, !weather.forecasts.isEmpty {
                    WeatherCreditView(credit: credit)
                        .padding(.vertical, 18)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .opacity(jumpOpacity)
            .offset(y: jumpOffset)
        }
        .scrollPosition($position, anchor: .top)
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.top, 6, for: .scrollContent)
        .onScrollPhaseChange { _, phase in
            userScrolling = phase == .interacting || phase == .decelerating || phase == .tracking
        }
        .onScrollTargetVisibilityChange(idType: Date.self, threshold: 0.2) { visible in
            visibleIDs = visible
            guard Date() > suppressSyncUntil, userScrolling, let first = visible.min() else { return }
            model.syncFromList(first)
        }
        .onChange(of: model.scrollRequest) { _, request in
            guard let request else { return }
            scroll(to: request.day, in: items, animated: request.animated)
        }
        .task {
            scroll(to: model.selectedDate, in: items, animated: false)
            try? await Task.sleep(for: .milliseconds(60))
            scroll(to: model.selectedDate, in: self.items, animated: false)
        }
    }

    private func scroll(to day: Date, in items: Array<AgendaItem>, animated: Bool) {
        guard let targetIndex = items.firstIndex(where: { $0.contains(day) }) else { return }
        let target = items[targetIndex].id
        let currentIndex = visibleIDs.min().flatMap { top in items.firstIndex { $0.contains(top) } }
        suppressSyncUntil = Date().addingTimeInterval(0.8)
        settle?.cancel()
        if animated, let currentIndex, abs(targetIndex - currentIndex) <= 2 {
            setJump(opacity: 1, offset: 0)
            withAnimation(.smooth(duration: 0.32)) {
                position.scrollTo(id: target, anchor: .top)
            }
            return
        }
        guard animated else {
            setJump(opacity: 1, offset: 0)
            settle = Task { await converge(on: target) }
            return
        }
        let direction: CGFloat = targetIndex >= (currentIndex ?? targetIndex) ? 1 : -1
        settle = Task {
            withAnimation(.easeIn(duration: 0.08)) { jumpOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            setJump(opacity: 0, offset: reduceMotion ? 0 : 14 * direction)
            await converge(on: target)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) {
                jumpOpacity = 1
                jumpOffset = 0
            }
            suppressSyncUntil = Date().addingTimeInterval(0.4)
        }
    }

    private func converge(on target: Date) async {
        for _ in 0..<10 {
            jump(to: target)
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            if visibleIDs.contains(target) {
                jump(to: target)
                return
            }
        }
    }

    private func setJump(opacity: Double, offset: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            jumpOpacity = opacity
            jumpOffset = offset
        }
    }

    private func jump(to id: Date) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(id: id, anchor: .top)
        }
    }
}

struct DayHeader: View {
    let date: Date
    let forecast: DayForecast?
    var allowsCompose = true
    @Environment(PanelModel.self) private var model
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    var body: some View {
        let today = date.isToday
        HStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.dayHeadline(date))
                    .font(.system(size: metrics.headerSize, weight: .bold))
                    .foregroundStyle(today ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                Text(Fmt.daySubline(date))
                    .font(.system(size: metrics.headerSize - 1.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if allowsCompose, hovering {
                Button {
                    model.compose(on: date)
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(L.newEvent)
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(RowButtonStyle(cornerRadius: 10))
                .foregroundStyle(.secondary)
                .help(L.newEventOn(Fmt.longDay(date)))
                .transition(.opacity)
            }
            if let forecast {
                WeatherBadge(forecast: forecast)
            }
        }
        .lineLimit(1)
        .frame(height: 20)
        .padding(.horizontal, 12)
        .padding(.top, metrics.headerTop)
        .padding(.bottom, metrics.compact ? 2 : 5)
        .contentShape(.rect)
        .onHover { inside in
            withAnimation(Motion.fade) { hovering = inside }
        }
        .onTapGesture {
            withAnimation(Motion.select) {
                model.select(date, scroll: false)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if allowsCompose { model.compose(on: date) }
            }
        )
        .accessibilityAddTraits([.isHeader, .isButton])
    }
}

private struct GapRow: View {
    let start: Date
    let end: Date
    @Environment(PanelModel.self) private var model
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.gapRange(start, end))
                .font(.system(size: metrics.metaSize, weight: .medium))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
            Text(L.nothingPlanned)
                .font(.system(size: metrics.metaSize))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: metrics.compact ? 26 : 36)
        .contentShape(.rect)
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            withAnimation(Motion.select) {
                model.select(start, scroll: false)
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.compose(on: start) })
    }
}

private enum DayRow: Identifiable {
    case event(Occurrence)
    case free(TimeInterval, Date)
    case now(Date)
    case reminder(ReminderItem)
    case empty

    var id: String {
        switch self {
        case .event(let occurrence): "e\(occurrence.id)"
        case .free(_, let date): "f\(date.timeIntervalSinceReferenceDate)"
        case .now: "now"
        case .reminder(let item): "r\(item.id)"
        case .empty: "empty"
        }
    }
}

private struct DaySectionContent: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @Environment(PanelModel.self) private var model
    @Environment(\.metrics) private var metrics

    private var rows: Array<DayRow> {
        let now = model.now
        let occurrences = store.occurrences(on: date)
        let isToday = date.isToday
        let showsFuture = date >= now.startOfDay
        var rows: Array<DayRow> = []
        let liveNow = occurrences.contains { !$0.isAllDay && !$0.spansMultipleDays && !$0.isDeclined && $0.isLive(at: now) }
        var placedNow = !isToday || liveNow
        var lastEnd: Date?
        for occurrence in occurrences {
            let timed = !occurrence.isAllDay && !occurrence.spansMultipleDays
            if timed, !placedNow, occurrence.start > now {
                rows.append(.now(now))
                placedNow = true
                lastEnd = max(lastEnd ?? now, now)
            }
            if timed, showsFuture, let previous = lastEnd, occurrence.start.timeIntervalSince(previous) >= 45 * 60, occurrence.start > now {
                rows.append(.free(occurrence.start.timeIntervalSince(previous), previous))
            }
            rows.append(.event(occurrence))
            if timed {
                lastEnd = max(lastEnd ?? occurrence.end, occurrence.end)
            }
        }
        if !placedNow, isToday, !occurrences.isEmpty {
            rows.append(.now(now))
        }
        for item in store.reminders(on: date) {
            rows.append(.reminder(item))
        }
        if rows.isEmpty {
            rows.append(.empty)
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(rows) { row in
                switch row {
                case .event(let occurrence):
                    if occurrence.birthday != nil {
                        BirthdayRow(occurrence: occurrence)
                    } else {
                        AgendaEventRow(occurrence: occurrence, day: date)
                    }
                case .free(let interval, _):
                    FreeTimeRow(interval: interval)
                case .now(let now):
                    NowMarker(now: now)
                case .reminder(let item):
                    ReminderRow(item: item)
                case .empty:
                    Text(L.freeRestOfDay)
                        .font(.system(size: metrics.metaSize))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, metrics.timeWidth + 30)
                        .frame(height: metrics.compact ? 24 : 32)
                }
            }
        }
        .padding(.top, 2)
    }
}

struct AgendaEventRow: View {
    let occurrence: Occurrence
    let day: Date

    @Environment(PanelModel.self) private var model
    @Environment(\.metrics) private var metrics

    private var timeLabels: (String, String?) {
        if occurrence.isAllDay { return (L.allDay, nil) }
        let startsToday = occurrence.start.isSameDay(as: day)
        let endsToday = occurrence.end.addingTimeInterval(-1).isSameDay(as: day)
        switch (startsToday, endsToday) {
        case (true, true): return (Fmt.time(occurrence.start), Fmt.time(occurrence.end))
        case (true, false): return (Fmt.time(occurrence.start), nil)
        case (false, true): return (Fmt.time(occurrence.end), nil)
        case (false, false): return (L.allDay, nil)
        }
    }

    var body: some View {
        let now = model.now
        let live = occurrence.isLive(at: now)
        let past = occurrence.end <= now && !occurrence.isAllDay
        let labels = timeLabels
        let joinable = occurrence.meeting != nil && occurrence.end > now && occurrence.start.timeIntervalSince(now) < 15 * 60
        ZStack(alignment: .trailing) {
            Button {
                model.show(occurrence)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(labels.0)
                            .font(.system(size: metrics.timeSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(live ? AnyShapeStyle(occurrence.color) : AnyShapeStyle(.secondary))
                        if let end = labels.1, !metrics.compact {
                            Text(end)
                                .font(.system(size: metrics.timeSize).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: metrics.timeWidth, alignment: .trailing)

                    ProgressBar(
                        color: occurrence.color, progress: live ? occurrence.progress(at: now) : (past ? 1 : 0),
                        outlined: occurrence.isPendingInvite
                    )
                    .frame(width: metrics.compact ? 3 : 4)
                    .padding(.vertical, 2)

                    if metrics.compact {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            title
                            if let meta = metaLine {
                                Text(meta)
                                    .font(.system(size: metrics.metaSize))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            title
                                .lineLimit(2)
                            if let meta = metaLine {
                                HStack(spacing: 4) {
                                    if let meeting = occurrence.meeting {
                                        MeetingGlyph(service: meeting.service, size: 10.5)
                                    }
                                    Text(meta)
                                        .lineLimit(1)
                                }
                                .font(.system(size: metrics.metaSize))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: joinable ? 70 : 0)
                }
                .padding(.vertical, metrics.rowPadding)
                .padding(.horizontal, 6)
                .frame(minHeight: metrics.rowHeight)
                .background {
                    if live {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(occurrence.color.opacity(0.14))
                    }
                }
            }
            .buttonStyle(RowButtonStyle())
            .contextMenu { EventContextMenu(occurrence: occurrence) }
            if joinable, let meeting = occurrence.meeting {
                JoinButton(meeting: meeting, prominent: live)
                    .padding(.trailing, 8)
            }
        }
        .opacity(past ? 0.55 : 1)
    }

    private var title: some View {
        Text(occurrence.title)
            .font(.system(size: metrics.titleSize, weight: .medium))
            .strikethrough(occurrence.isDeclined)
            .foregroundStyle(occurrence.isDeclined ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }

    private var metaLine: String? {
        if let location = occurrence.location { return location }
        return occurrence.meeting?.service.name
    }
}

struct BirthdayRow: View {
    let occurrence: Occurrence
    @Environment(PanelModel.self) private var model
    @Environment(ContactsModel.self) private var contacts
    @Environment(\.metrics) private var metrics
    @State private var bounce = 0

    var body: some View {
        let birthday = occurrence.birthday
        Button {
            model.show(occurrence)
        } label: {
            HStack(spacing: 10) {
                let avatar: CGFloat = metrics.compact ? 20 : 30
                ContactAvatar(
                    card: birthday.flatMap { contacts.card(forBirthday: $0) }, name: birthday?.name ?? occurrence.title, size: avatar
                )
                .overlay(alignment: .bottomTrailing) {
                    BirthdayGlyph(size: avatar * 0.3, bounce: bounce)
                        .padding(avatar * 0.08)
                        .background(.regularMaterial, in: .circle)
                        .offset(x: avatar * 0.18, y: avatar * 0.12)
                }
                .padding(.trailing, avatar * 0.18)
                .frame(width: metrics.timeWidth, alignment: .trailing)
                SprinkleBar(width: metrics.compact ? 3 : 4)
                    .padding(.vertical, 2)
                Group {
                    if metrics.compact {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            name
                            age
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            name
                            age
                        }
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, metrics.rowPadding)
            .padding(.horizontal, 6)
            .frame(minHeight: metrics.rowHeight)
        }
        .buttonStyle(RowButtonStyle())
        .onHover { if $0 { bounce += 1 } }
        .contextMenu { EventContextMenu(occurrence: occurrence) }
        .accessibilityLabel("\(birthday?.name ?? occurrence.title), \(birthday?.ageLine(on: occurrence.start) ?? L.birthday)")
    }

    private var name: some View {
        Text(occurrence.birthday?.name ?? occurrence.title)
            .font(.system(size: metrics.titleSize, weight: .semibold))
    }

    private var age: some View {
        Text(occurrence.birthday?.ageLine(on: occurrence.start) ?? L.birthday)
            .font(.system(size: metrics.metaSize, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

private struct FreeTimeRow: View {
    let interval: TimeInterval
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: metrics.timeWidth)
            Rectangle()
                .fill(.primary.opacity(0.14))
                .frame(width: 4, height: 1)
            Text(L.freeTime(Fmt.duration(interval)))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .frame(height: metrics.compact ? 16 : 22)
    }
}

private struct NowMarker: View {
    let now: Date
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            Text(Fmt.time(now))
                .font(.system(size: metrics.timeSize - 0.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.red)
                .frame(width: metrics.timeWidth, alignment: .trailing)
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .padding(.leading, 8)
            Rectangle()
                .fill(.red.opacity(0.75))
                .frame(height: 1.2)
        }
        .padding(.horizontal, 6)
        .frame(height: metrics.compact ? 12 : 18)
        .accessibilityLabel(L.now)
    }
}

struct ReminderRow: View {
    let item: ReminderItem
    @Environment(CalendarStore.self) private var store
    @Environment(\.metrics) private var metrics
    @State private var done = false

    var body: some View {
        HStack(spacing: 10) {
            Text(item.hasTime ? Fmt.time(item.due) : (item.due < Date().startOfDay ? L.overdue : ""))
                .font(.system(size: metrics.timeSize, weight: .medium).monospacedDigit())
                .foregroundStyle(item.due < Date().startOfDay ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .frame(width: metrics.timeWidth, alignment: .trailing)
            Button {
                withAnimation(.snappy(duration: 0.25)) { done = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    store.complete(item)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.color, lineWidth: 1.5)
                    if done {
                        Circle()
                            .fill(item.color)
                            .padding(3)
                            .transition(.scale)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(done ? .isSelected : [])
            .help(L.completeReminder)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: metrics.titleSize))
                    .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(metrics.compact ? 1 : 2)
                if !metrics.compact {
                    Text(item.listTitle)
                        .font(.system(size: metrics.metaSize - 0.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, metrics.rowPadding)
        .padding(.horizontal, 6)
        .frame(minHeight: metrics.rowHeight)
    }
}
