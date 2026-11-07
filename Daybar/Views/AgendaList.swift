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

struct AgendaLayout: Equatable {
    var compact = false
    var separateAllDay = false
    var remindersByTime = false
}

extension EnvironmentValues {
    @Entry var agendaLayout = AgendaLayout()
}

struct AgendaList: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather
    @Environment(Preferences.self) private var prefs
    @Environment(\.metrics) private var metrics
    @State private var position = ScrollPosition(id: Date().startOfDay, anchor: .top)
    @State private var pendingTarget: Date?
    @State private var shownLayout: AgendaLayout?
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

    private var liveLayout: AgendaLayout {
        AgendaLayout(compact: metrics.compact, separateAllDay: prefs.separateAllDay, remindersByTime: prefs.remindersByTime)
    }

    var body: some View {
        let items = items
        let layout = shownLayout ?? liveLayout
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    switch item {
                    case .day(let date):
                        VStack(alignment: .leading, spacing: 0) {
                            DayHeader(date: date, forecast: weather.forecast(for: date))
                            DaySectionContent(date: date)
                                .padding(.bottom, layout.compact ? 2 : 8)
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
            .environment(\.metrics, Metrics(compact: layout.compact))
            .environment(\.agendaLayout, layout)
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
        .onChange(of: liveLayout) { restyle(in: items) }
        .onChange(of: store.range.start) { pin(in: items) }
        .task {
            settleLayout()
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
        settleLayout()
        if animated, let currentIndex, abs(targetIndex - currentIndex) <= 2 {
            pendingTarget = nil
            setJump(opacity: 1, offset: 0)
            withAnimation(.smooth(duration: 0.32)) {
                position.scrollTo(id: target, anchor: .top)
            }
            return
        }
        pendingTarget = target
        guard animated else {
            setJump(opacity: 1, offset: 0)
            settle = Task {
                await converge(on: target)
                if !Task.isCancelled { pendingTarget = nil }
            }
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
            pendingTarget = nil
            suppressSyncUntil = Date().addingTimeInterval(0.4)
        }
    }

    private func pin(in items: Array<AgendaItem>) {
        guard pendingTarget == nil, let target = anchor(in: items) else { return }
        suppressSyncUntil = Date().addingTimeInterval(0.8)
        settle?.cancel()
        settleLayout()
        setJump(opacity: 1, offset: 0)
        settle = Task { await converge(on: target) }
    }

    private func restyle(in items: Array<AgendaItem>) {
        guard pendingTarget == nil else {
            settleLayout()
            return
        }
        let target = anchor(in: items)
        suppressSyncUntil = Date().addingTimeInterval(1)
        settle?.cancel()
        settle = Task {
            if !reduceMotion {
                withAnimation(.easeIn(duration: 0.1)) { jumpOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            setJump(opacity: reduceMotion ? 1 : 0, offset: 0)
            settleLayout()
            if let target { await converge(on: target) }
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.28)) { jumpOpacity = 1 }
            suppressSyncUntil = Date().addingTimeInterval(0.3)
        }
    }

    private func settleLayout() {
        guard shownLayout != liveLayout else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { shownLayout = liveLayout }
    }

    private func anchor(in items: Array<AgendaItem>) -> Date? {
        if let selected = items.first(where: { $0.contains(model.selectedDate) })?.id, visibleIDs.contains(selected) {
            return selected
        }
        return visibleIDs.min()
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
    case remindersHeading
    case empty

    var id: String {
        switch self {
        case .event(let occurrence): "e\(occurrence.id)"
        case .free(_, let date): "f\(date.timeIntervalSinceReferenceDate)"
        case .now: "now"
        case .reminder(let item): "r\(item.id)"
        case .remindersHeading: "reminders"
        case .empty: "empty"
        }
    }

    func comes(after moment: Date) -> Bool {
        switch self {
        case .event(let occurrence): !occurrence.isAllDay && occurrence.start > moment
        case .free(_, let date): date > moment
        case .now(let now): now > moment
        case .reminder(let item): item.sortMoment > moment
        case .remindersHeading, .empty: false
        }
    }
}

private struct DaySectionContent: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @Environment(PanelModel.self) private var model
    @Environment(\.agendaLayout) private var layout
    @Environment(\.metrics) private var metrics

    private var banner: Array<Occurrence> {
        guard layout.separateAllDay else { return [] }
        return store.occurrences(on: date).filter { $0.fills(date) }
    }

    private func rows(excluding banner: Array<Occurrence>) -> Array<DayRow> {
        let now = model.now
        let hidden = Set(banner.map(\.id))
        let occurrences = store.occurrences(on: date).filter { !hidden.contains($0.id) }
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
        let reminders = store.reminders(on: date)
        if layout.remindersByTime {
            for item in reminders {
                let index = rows.firstIndex { $0.comes(after: item.sortMoment) } ?? rows.endIndex
                rows.insert(.reminder(item), at: index)
            }
        } else if !reminders.isEmpty {
            if !rows.isEmpty || !banner.isEmpty { rows.append(.remindersHeading) }
            for item in reminders {
                rows.append(.reminder(item))
            }
        }
        if rows.isEmpty, banner.isEmpty || isToday {
            rows.append(.empty)
        }
        return rows
    }

    var body: some View {
        let banner = banner
        VStack(alignment: .leading, spacing: 1) {
            if !banner.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(banner) { occurrence in
                        AllDayChip(occurrence: occurrence, day: date, fills: false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, metrics.compact ? 3 : 5)
                .transition(.opacity)
            }
            ForEach(rows(excluding: banner)) { row in
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
                case .remindersHeading:
                    RemindersHeading()
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

private struct RemindersHeading: View {
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: metrics.timeWidth)
            Text(L.remindersHeading)
                .font(.system(size: metrics.metaSize - 0.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, -2)
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.horizontal, 6)
        .padding(.top, metrics.compact ? 4 : 8)
        .frame(height: metrics.compact ? 20 : 26, alignment: .bottom)
        .accessibilityAddTraits(.isHeader)
    }
}
