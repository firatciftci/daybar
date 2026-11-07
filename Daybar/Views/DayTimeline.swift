import SwiftUI

struct DayTimelineLayout: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather

    var body: some View {
        let day = model.selectedDate
        let allDay = store.occurrences(on: day).filter { $0.isAllDay || $0.spansMultipleDays }
        VStack(spacing: 0) {
            CalendarHeader(style: .week)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            WeekStrip()
                .padding(.horizontal, 10)
                .zIndex(2)
            LowerPane {
                VStack(spacing: 0) {
                    DayHeader(date: day, forecast: weather.forecast(for: day))
                        .padding(.horizontal, 8)
                    if !allDay.isEmpty {
                        VStack(spacing: 3) {
                            ForEach(allDay) { occurrence in
                                AllDayChip(occurrence: occurrence, day: day)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    TimelineScroll(day: day)
                        .id(day)
                        .transition(.push(from: model.gridDirection > 0 ? .trailing : .leading))
                }
            }
        }
    }
}

private struct TimedBlock: Identifiable {
    let occurrence: Occurrence
    let column: Int
    let columns: Int
    var id: String { occurrence.id }
}

private struct TimelineScroll: View {
    let day: Date
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs

    private let hourHeight: CGFloat = 46
    @State private var position = ScrollPosition()
    private let gutter: CGFloat = 58
    @State private var draft: (start: Double, end: Double)?
    @State private var dragging: (id: String, offset: CGFloat)?

    private var blocks: Array<TimedBlock> {
        let timed = store.occurrences(on: day).filter { !$0.isAllDay && !$0.spansMultipleDays }
        var result: Array<TimedBlock> = []
        var cluster: Array<Occurrence> = []
        var clusterEnd = Date.distantPast
        func flush() {
            var columnEnds: Array<Date> = []
            var assigned: Array<(Occurrence, Int)> = []
            for occurrence in cluster {
                if let index = columnEnds.firstIndex(where: { $0 <= occurrence.start }) {
                    columnEnds[index] = occurrence.end
                    assigned.append((occurrence, index))
                } else {
                    columnEnds.append(occurrence.end)
                    assigned.append((occurrence, columnEnds.count - 1))
                }
            }
            for (occurrence, column) in assigned {
                result.append(TimedBlock(occurrence: occurrence, column: column, columns: columnEnds.count))
            }
            cluster = []
        }
        for occurrence in timed {
            if occurrence.start >= clusterEnd, !cluster.isEmpty { flush() }
            cluster.append(occurrence)
            clusterEnd = max(clusterEnd, occurrence.end)
        }
        flush()
        return result
    }

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let width = proxy.size.width - gutter - 10
                ZStack(alignment: .topLeading) {
                    hourGrid(width: proxy.size.width)
                    Color.clear
                        .contentShape(.rect)
                        .frame(width: width, height: hourHeight * 24)
                        .offset(x: gutter)
                        .gesture(createGesture)
                        .simultaneousGesture(
                            SpatialTapGesture(count: 2).onEnded { value in
                                let minutes = (value.location.y / hourHeight * 60 / 30).rounded(.down) * 30
                                model.compose(start: date(at: minutes), end: date(at: minutes + 60))
                            })
                    if let draft {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.25))
                            .overlay(alignment: .topLeading) {
                                Text(Fmt.timeRange(date(at: min(draft.start, draft.end)), date(at: max(draft.start, draft.end))))
                                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .padding(4)
                            }
                            .frame(width: width, height: max(12, abs(draft.end - draft.start) / 60 * hourHeight))
                            .offset(x: gutter, y: min(draft.start, draft.end) / 60 * hourHeight)
                    }
                    ForEach(blocks) { block in
                        blockView(block, width: width)
                    }
                    if day.isToday {
                        nowLine(width: proxy.size.width)
                    }
                }
            }
            .frame(height: hourHeight * 24)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollPosition($position)
        .task(id: day) {
            let nowHour = Calendar.current.component(.hour, from: .now)
            let earliest =
                blocks.map { Calendar.current.component(.hour, from: $0.occurrence.start) }.filter { $0 >= nowHour - 4 }.min() ?? nowHour
            let anchorHour = day.isToday ? max(0, min(nowHour - 1, earliest)) : firstHour
            position.scrollTo(y: CGFloat(anchorHour) * hourHeight)
        }
    }

    private var firstHour: Int {
        let first = blocks.map { Calendar.current.component(.hour, from: $0.occurrence.start) }.min() ?? 8
        return max(0, min(first, 8) - 1)
    }

    private func hourGrid(width: CGFloat) -> some View {
        let zone = prefs.secondTimeZone
        return VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                let hourDate = date(at: Double(hour * 60))
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(hour == 0 ? "" : Fmt.shortHour(hourDate))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let zone, hour != 0 {
                            Text(Fmt.shortHour(hourDate, in: zone))
                                .font(.system(size: 9.5).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: -6)
                    .opacity(day.isToday && abs(model.now.minutesIntoDay - Double(hour * 60)) < 14 ? 0 : 1)
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
        .frame(width: width)
    }

    private func blockView(_ block: TimedBlock, width: CGFloat) -> some View {
        let occurrence = block.occurrence
        let columnWidth = width / CGFloat(block.columns)
        let top = occurrence.start.minutesIntoDay / 60 * hourHeight
        let height = max(18, occurrence.duration / 3_600 * hourHeight - 2)
        let shift = dragging?.id == occurrence.id ? dragging?.offset ?? 0 : 0
        let live = occurrence.isLive(at: model.now)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(occurrence.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(height > 34 ? 2 : 1)
                if height > 30 {
                    Text(Fmt.timeRange(occurrence.start, occurrence.end))
                        .font(.system(size: 10.5).monospacedDigit())
                        .opacity(0.8)
                }
            }
            .foregroundStyle(occurrence.color.mix(with: .primary, by: 0.45))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
            if let meeting = occurrence.meeting, occurrence.end > model.now {
                Button {
                    meeting.join()
                } label: {
                    MeetingGlyph(service: meeting.service, size: 11)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(occurrence.color.mix(with: .primary, by: 0.45))
                .help(L.joinService(meeting.service.name))
            }
        }
        .frame(width: columnWidth - 2, height: height, alignment: .top)
        .background(occurrence.color.opacity(live ? 0.32 : 0.2), in: .rect(cornerRadius: 6, style: .continuous))
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .opacity(occurrence.isDeclined ? 0.5 : 1)
        .scaleEffect(dragging?.id == occurrence.id ? 1.02 : 1)
        .shadow(color: .black.opacity(dragging?.id == occurrence.id ? 0.18 : 0), radius: 8, y: 3)
        .offset(x: gutter + CGFloat(block.column) * columnWidth, y: top + shift)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { model.show(occurrence) }
        .gesture(moveGesture(for: occurrence))
        .contextMenu { EventContextMenu(occurrence: occurrence) }
    }

    private func nowLine(width: CGFloat) -> some View {
        let y = model.now.minutesIntoDay / 60 * hourHeight
        return HStack(spacing: 0) {
            Text(Fmt.time(model.now))
                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .frame(height: 15)
                .background(.red, in: .capsule)
                .frame(width: gutter, alignment: .trailing)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
        .frame(width: width)
        .offset(y: y - 7.5)
        .allowsHitTesting(false)
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = snap(value.startLocation.y / hourHeight * 60)
                let end = snap(value.location.y / hourHeight * 60)
                draft = (start, end == start ? start + 15 : end)
            }
            .onEnded { _ in
                guard let draft else { return }
                let start = date(at: min(draft.start, draft.end))
                let end = date(at: max(draft.start, draft.end))
                self.draft = nil
                model.compose(start: start, end: end.timeIntervalSince(start) < 900 ? start.addingTimeInterval(1_800) : end)
            }
    }

    private func moveGesture(for occurrence: Occurrence) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let minutes = snap(value.translation.height / hourHeight * 60)
                dragging = (occurrence.id, minutes / 60 * hourHeight)
            }
            .onEnded { value in
                let minutes = snap(value.translation.height / hourHeight * 60)
                dragging = nil
                guard minutes != 0 else { return }
                let delta = minutes * 60
                withAnimation(Motion.select) {
                    store.move(occurrence, to: occurrence.start.addingTimeInterval(delta), end: occurrence.end.addingTimeInterval(delta))
                }
            }
    }

    private func snap(_ minutes: Double) -> Double {
        (minutes / 15).rounded() * 15
    }

    private func date(at minutes: Double) -> Date {
        Calendar.current.date(byAdding: .minute, value: Int(max(0, min(minutes, 24 * 60))), to: day) ?? day
    }
}
