import SwiftUI

struct AllDayChip: View {
    let occurrence: Occurrence
    let day: Date
    var fills = true
    @Environment(PanelModel.self) private var model
    @Environment(ContactsModel.self) private var contacts
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button {
            model.show(occurrence)
        } label: {
            label
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 6, hoverable: false))
        .contextMenu { EventContextMenu(occurrence: occurrence) }
    }

    private var label: some View {
        let continuesBefore = occurrence.start < day.startOfDay
        let continuesAfter = occurrence.end.addingTimeInterval(-1).startOfDay > day.startOfDay
        let tint = occurrence.color.mix(with: .primary, by: 0.35)
        return HStack(spacing: 6) {
            if continuesBefore {
                continuation("chevron.compact.left", tint: tint)
            }
            if let birthday = occurrence.birthday {
                ContactAvatar(card: contacts.card(forBirthday: birthday), name: birthday.name, size: 16)
                    .padding(.leading, -4)
                Text(birthday.name)
                    .foregroundStyle(.primary)
                Text(birthday.ageLine(on: occurrence.start))
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                if fills { Spacer(minLength: 0) }
                BirthdayGlyph(size: 11)
            } else {
                Text(occurrence.title)
                    .foregroundStyle(tint)
                    .strikethrough(occurrence.isDeclined)
                if fills { Spacer(minLength: 0) }
            }
            if continuesAfter {
                continuation("chevron.compact.right", tint: tint)
            }
        }
        .font(.system(size: metrics.compact ? 11 : 11.5, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        .frame(height: metrics.compact ? 20 : 22)
        .background(occurrence.birthday == nil ? occurrence.color.opacity(0.2) : Color.pink.opacity(0.14), in: .rect(cornerRadius: 6))
        .overlay {
            if occurrence.isPendingInvite {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(occurrence.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .opacity(occurrence.isDeclined ? 0.6 : 1)
    }

    private func continuation(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint.opacity(0.7))
            .padding(.horizontal, -2)
            .accessibilityHidden(true)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: Array<CGRect>, size: CGSize) {
        var frames: Array<CGRect> = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: min(size.width, width), height: size.height)))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: min(widest, width), height: y + lineHeight))
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

struct FreeTimeRow: View {
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

struct NowMarker: View {
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
