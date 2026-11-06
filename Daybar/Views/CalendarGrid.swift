import SwiftUI

enum GridStyle {
    case month
    case week
}

struct CalendarListLayout: View {
    let style: GridStyle

    var body: some View {
        VStack(spacing: 0) {
            CalendarHeader(style: style)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            Group {
                switch style {
                case .month: MonthGrid()
                case .week: WeekStrip()
                }
            }
            .padding(.horizontal, 10)
            .zIndex(2)
            LowerPane {
                AgendaList()
            }
            .zIndex(1)
        }
    }
}

struct CalendarHeader: View {
    let style: GridStyle
    @Environment(PanelModel.self) private var model
    @Environment(Preferences.self) private var prefs
    @State private var pressing = false
    @State private var picking = false

    private var reference: Date {
        style == .month ? model.displayedMonth : model.selectedDate
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    "\(Text(Fmt.monthName(reference)).font(.system(size: 17, weight: .bold))) \(Text(Fmt.year(reference)).font(.system(size: 17, weight: .regular)).foregroundStyle(.secondary))"
                )
                .contentTransition(.numericText(countsDown: model.gridDirection < 0))
                .animation(.snappy, value: reference)
                .opacity(pressing ? 0.55 : 1)
                .contentShape(.rect)
                .onTapGesture(count: 2) {
                    withAnimation(Motion.navigate) { model.goToToday() }
                }
                .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12) {
                    picking = true
                } onPressingChanged: { inside in
                    withAnimation(Motion.fade) { pressing = inside }
                }
                .help(L.monthTitleHelp)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    MonthYearPicker(reference: reference) { month in
                        picking = false
                        withAnimation(Motion.navigate) { model.showMonth(month) }
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: L.chooseMonth) { picking = true }
                if let zone = prefs.secondTimeZone {
                    Text("\(Fmt.zoneName(zone)) \(Fmt.time(model.now, in: zone))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if prefs.showWeekNumbers, style == .week {
                    Text(L.weekNumber(Calendar.daybar.component(.weekOfYear, from: model.selectedDate)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            NavigationCluster(
                onPrevious: { step(-1) },
                onToday: { withAnimation(Motion.navigate) { model.goToToday() } },
                onNext: { step(1) }
            )
        }
    }

    private func step(_ delta: Int) {
        withAnimation(Motion.navigate) {
            if style == .month {
                model.shiftMonth(delta)
            } else {
                model.shift(days: delta * 7)
            }
        }
    }
}

struct NavigationCluster: View {
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", L.previous, onPrevious)
            Button(action: onToday) {
                Text(L.today)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
            }
            .buttonStyle(RowButtonStyle(cornerRadius: 13, hoverable: false))
            .help(L.goToToday)
            .keyboardShortcut("t", modifiers: .command)
            button("chevron.right", L.next, onNext)
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 13, hoverable: false))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct WeekdayLabels: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        let calendar = Calendar.daybar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        HStack(spacing: 0) {
            if leadingInset > 0 {
                Color.clear.frame(width: leadingInset)
            }
            ForEach(0..<7, id: \.self) { offset in
                let index = (first + offset) % 7
                Text(symbols[index])
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(index == 0 || index == 6 ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct MonthGrid: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs
    @Environment(\.metrics) private var metrics
    @Namespace private var lens
    @State private var hover = SummaryHover()

    private var weeks: Array<Array<Date>> {
        let start = model.displayedMonth.startOfWeek
        return (0..<6).map { week in
            (0..<7).map { day in start.adding(days: week * 7 + day) }
        }
    }

    var body: some View {
        let numberInset: CGFloat = prefs.showWeekNumbers ? 22 : 0
        let weeks = weeks
        VStack(spacing: 0) {
            WeekdayLabels(leadingInset: numberInset)
                .padding(.top, metrics.compact ? 6 : 10)
                .padding(.bottom, 4)
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.first) { week in
                        HStack(spacing: 0) {
                            if prefs.showWeekNumbers, let first = week.first {
                                Text("\(Calendar.daybar.component(.weekOfYear, from: first))")
                                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: numberInset)
                            }
                            ForEach(week, id: \.self) { date in
                                let inMonth = date.isSameMonth(as: model.displayedMonth)
                                DayCell(
                                    date: date,
                                    inMonth: inMonth,
                                    isSelected: date.isSameDay(as: model.selectedDate) && inMonth,
                                    occurrences: store.occurrences(on: date),
                                    lens: lens,
                                    mark: model.mark(for: date)
                                )
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture {
                                    hover.dismiss()
                                    withAnimation(Motion.select) {
                                        model.pick(date)
                                    }
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { model.compose(on: date) })
                                .onHover { inside in hover.update(date, inside: inside, hasContent: hasContent(date)) }
                            }
                        }
                        .frame(height: metrics.gridRow)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    if let summary = hover.date, let row = weeks.firstIndex(where: { $0.contains { $0.isSameDay(as: summary) } }),
                        let column = weeks[row].firstIndex(where: { $0.isSameDay(as: summary) })
                    {
                        let cardWidth: CGFloat = 248
                        let cell = (proxy.size.width - numberInset) / 7
                        let center = numberInset + (CGFloat(column) + 0.5) * cell
                        let x = min(max(0, center - cardWidth / 2), proxy.size.width - cardWidth)
                        let above = row >= 3
                        let y = above ? CGFloat(row) * metrics.gridRow + 2 : CGFloat(row + 1) * metrics.gridRow - 2
                        DaySummaryCard(date: summary)
                            .frame(width: cardWidth)
                            .alignmentGuide(.top) { dimensions in above ? dimensions.height : 0 }
                            .offset(x: x, y: y)
                            .transition(.scale(scale: 0.97, anchor: above ? .bottom : .top).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
            }
            .id(model.displayedMonth)
            .transition(.push(from: model.gridDirection > 0 ? .trailing : .leading))
        }
        .padding(.bottom, 4)
        .onHorizontalSwipe { delta in
            hover.dismiss()
            withAnimation(Motion.navigate) {
                model.shiftMonth(delta)
            }
        }
    }

    private func hasContent(_ date: Date) -> Bool {
        !store.occurrences(on: date).isEmpty || !store.reminders(on: date).isEmpty
    }
}

private struct KeyWindowActivator: NSViewRepresentable {
    func makeNSView(context _: Context) -> ActivatorView {
        ActivatorView()
    }

    func updateNSView(_: ActivatorView, context _: Context) {}

    final class ActivatorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeKey()
        }
    }
}

@Observable
final class SummaryHover {
    var date: Date?
    @ObservationIgnored private var hovered: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    func update(_ day: Date, inside: Bool, hasContent: Bool) {
        if inside {
            hovered = day
            task?.cancel()
            let delay = date == nil ? 520 : 60
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !Task.isCancelled else { return }
                withAnimation(self.date == nil ? Motion.fade : Motion.select) {
                    self.date = hasContent ? day : nil
                }
            }
        } else if hovered == day {
            hovered = nil
            task?.cancel()
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard let self, !Task.isCancelled else { return }
                withAnimation(Motion.fade) { self.date = nil }
            }
        }
    }

    func dismiss() {
        hovered = nil
        task?.cancel()
        withAnimation(Motion.fade) { date = nil }
    }
}

private struct MonthYearPicker: View {
    let reference: Date
    let onPick: (Date) -> Void
    @State private var year: Int

    init(reference: Date, onPick: @escaping (Date) -> Void) {
        self.reference = reference
        self.onPick = onPick
        _year = State(initialValue: Calendar.daybar.component(.year, from: reference))
    }

    var body: some View {
        let calendar = Calendar.daybar
        let selectedMonth = calendar.component(.month, from: reference)
        let selectedYear = calendar.component(.year, from: reference)
        let currentMonth = calendar.component(.month, from: .now)
        let currentYear = calendar.component(.year, from: .now)
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                step("chevron.left", L.previousYear) { year = clamped(year - 1) }
                TextField(L.yearField, value: $year, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .onSubmit {
                        year = clamped(year)
                        onPick(month(selectedMonth))
                    }
                    .accessibilityLabel(L.yearField)
                step("chevron.right", L.nextYear) { year = clamped(year + 1) }
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<4, id: \.self) { row in
                    GridRow {
                        ForEach(1...3, id: \.self) { column in
                            let number = row * 3 + column
                            let selected = number == selectedMonth && year == selectedYear
                            let current = number == currentMonth && year == currentYear
                            Button {
                                onPick(month(number))
                            } label: {
                                Text(calendar.shortStandaloneMonthSymbols[number - 1])
                                    .font(.system(size: 13, weight: selected || current ? .semibold : .regular))
                                    .foregroundStyle(
                                        selected ? AnyShapeStyle(.white) : (current ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background {
                                        if selected {
                                            Capsule().fill(Color.accentColor)
                                        }
                                    }
                            }
                            .buttonStyle(RowButtonStyle(cornerRadius: 15))
                            .accessibilityLabel(calendar.standaloneMonthSymbols[number - 1])
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 244)
        .background(KeyWindowActivator())
    }

    private func month(_ number: Int) -> Date {
        Calendar.daybar.date(from: DateComponents(year: clamped(year), month: number, day: 1)) ?? reference
    }

    private func clamped(_ value: Int) -> Int {
        min(max(value, 1), 9_999)
    }

    private func step(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 14))
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct DaySummaryCard: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather

    var body: some View {
        let occurrences = store.occurrences(on: date)
        let reminders = store.reminders(on: date)
        let shown = Array(occurrences.prefix(5))
        let overflow = occurrences.count - shown.count + reminders.count
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Fmt.dayHeadline(date))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(date.isToday ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                Text(Fmt.daySubline(date))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let forecast = weather.forecast(for: date) {
                    WeatherBadge(forecast: forecast)
                }
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { occurrence in
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(occurrence.color)
                            .frame(width: 3, height: 14)
                        Group {
                            if occurrence.birthday != nil {
                                BirthdayGlyph(size: 10.5)
                            } else {
                                Text(occurrence.isAllDay || occurrence.spansMultipleDays ? L.allDay : Fmt.time(occurrence.start))
                            }
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                        Text(occurrence.birthday?.name ?? occurrence.title)
                            .font(.system(size: 12, weight: .medium))
                            .strikethrough(occurrence.isDeclined)
                            .lineLimit(1)
                    }
                }
                if overflow > 0 {
                    Text(L.moreEvents(overflow))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 11)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.72)), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }
}

struct WeekStrip: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(\.metrics) private var metrics
    @Namespace private var lens
    @State private var hover = SummaryHover()

    private var days: Array<Date> {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        let calendar = Calendar.daybar
        let days = days
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { date in
                    VStack(spacing: 3) {
                        Text(calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        DayCell(
                            date: date,
                            inMonth: true,
                            isSelected: date.isSameDay(as: model.selectedDate),
                            occurrences: store.occurrences(on: date),
                            lens: lens,
                            mark: model.mark(for: date),
                            large: true
                        )
                    }
                    .contentShape(.rect)
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        hover.dismiss()
                        withAnimation(Motion.select) {
                            model.pick(date)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            hover.dismiss()
                            model.compose(on: date)
                        }
                    )
                    .onHover { inside in
                        hover.update(
                            date, inside: inside, hasContent: !store.occurrences(on: date).isEmpty || !store.reminders(on: date).isEmpty)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                if let summary = hover.date, let column = days.firstIndex(where: { $0.isSameDay(as: summary) }) {
                    let cardWidth: CGFloat = 248
                    let cell = proxy.size.width / 7
                    let x = min(max(0, (CGFloat(column) + 0.5) * cell - cardWidth / 2), proxy.size.width - cardWidth)
                    DaySummaryCard(date: summary)
                        .frame(width: cardWidth)
                        .offset(x: x, y: proxy.size.height + 4)
                        .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .id(model.selectedDate.startOfWeek)
        .transition(.push(from: model.gridDirection > 0 ? .trailing : .leading))
        .padding(.top, metrics.compact ? 6 : 10)
        .padding(.bottom, metrics.compact ? 4 : 8)
        .onHorizontalSwipe { delta in
            withAnimation(Motion.navigate) {
                model.shift(days: delta * 7)
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isSelected: Bool
    let occurrences: Array<Occurrence>
    let lens: Namespace.ID
    var mark: DayMark = .plain
    var large = false
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    var body: some View {
        let today = date.isToday
        let diameter = metrics.dayDiameter + (large ? 3 : 0)
        let filled = today || isSelected
        VStack(spacing: metrics.compact ? 2 : 3) {
            ZStack {
                if today, !isSelected {
                    Circle()
                        .fill(Color.red)
                        .padding(2)
                } else if !filled {
                    Circle()
                        .fill(.primary.opacity(hovering ? 0.11 : 0))
                        .padding(1)
                }
                if mark == .ring, !filled {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .padding(1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Text("\(date.dayNumber)")
                    .font(
                        .system(size: metrics.dayFont + (large ? 1 : 0), weight: filled || mark == .ring ? .bold : .regular)
                            .monospacedDigit()
                    )
                    .foregroundStyle(filled ? AnyShapeStyle(.white) : (inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
                    .opacity(mark == .dim && !filled ? 0.35 : 1)
            }
            .frame(width: diameter, height: diameter)
            .glassEffect(isSelected ? .regular.tint(today ? .red : .accentColor).interactive() : .identity, in: .circle)
            .glassEffectID(isSelected ? "lens" : "day-\(date.timeIntervalSinceReferenceDate)", in: lens)
            DayFingerprint(occurrences: occurrences, width: large ? 24 : 20, height: metrics.compact ? 3 : 3.5)
                .opacity((inMonth ? 1 : 0.4) * (mark == .dim ? 0.3 : 1))
        }
        .animation(Motion.fade, value: mark)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Motion.fade, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Fmt.longDay(date))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
