import EventKit
import SwiftUI

struct RepeatRows: View {
    @Binding var rule: RepeatRule
    let start: Date

    var body: some View {
        Picker(L.repeatFrequency, selection: $rule.frequency.animation(.snappy)) {
            ForEach(RepeatRule.frequencies, id: \.self) { frequency in
                Text(RepeatRule.title(frequency)).tag(frequency)
            }
        }
        .onChange(of: rule.frequency) { _, frequency in
            if frequency == .weekly, rule.weekdays.isEmpty { rule.weekdays = [RepeatRule.weekday(of: start)] }
        }
        Stepper(value: $rule.interval, in: 1...99) {
            Text(RepeatRule.every(rule.frequency, rule.interval))
                .contentTransition(.numericText(value: Double(rule.interval)))
                .animation(.snappy, value: rule.interval)
        }
        if rule.frequency == .weekly {
            WeekdayChips(selection: $rule.weekdays)
        }
        if rule.frequency == .monthly {
            Picker(L.frequencyMonthly, selection: $rule.byWeekday) {
                Text(L.monthlyOnDate(RepeatRule.ordinalDay(of: start))).tag(false)
                Text(L.monthlyOnWeekday(RepeatRule.ordinalWord(of: start), RepeatRule.weekdayName(of: start))).tag(true)
            }
            .labelsHidden()
        }
        Picker(L.repeatEnd, selection: $rule.end.animation(.snappy)) {
            Text(L.repeatEndNever).tag(RepeatRule.End.never)
            Text(L.repeatEndOnDate).tag(RepeatRule.End.date)
            Text(L.repeatEndAfter).tag(RepeatRule.End.count)
        }
        if rule.end == .date {
            DatePicker(L.repeatEndDate, selection: $rule.endDate, in: start..., displayedComponents: .date)
        }
        if rule.end == .count {
            Stepper(value: $rule.count, in: 1...999) {
                Text(L.repeatCount(rule.count))
                    .contentTransition(.numericText(value: Double(rule.count)))
                    .animation(.snappy, value: rule.count)
            }
        }
    }
}

private struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RepeatRule.ordered(1...7), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        if selection.count > 1 { selection.remove(day) }
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(Calendar.daybar.veryShortStandaloneWeekdaySymbols[day - 1])
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.daybar.standaloneWeekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .animation(.snappy(duration: 0.18), value: isOn)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AlertRows: View {
    @Binding var alerts: Array<Int>
    let allDay: Bool
    let focus: FocusState<EditorField?>.Binding

    var body: some View {
        ForEach(0..<min(alerts.count + 1, L.alertRows.count), id: \.self) { index in
            if index == 0 {
                row(at: index).focused(focus, equals: .alert)
            } else {
                row(at: index)
            }
        }
    }

    private func row(at index: Int) -> some View {
        Picker(L.alertRows[index], selection: binding(at: index).animation(.snappy)) {
            Text(L.alertNone).tag(Int?.none)
            ForEach(AlertOffset.options(including: index < alerts.count ? alerts[index] : nil, allDay: allDay), id: \.self) { minutes in
                Text(AlertOffset.title(minutes, allDay: allDay)).tag(Int?.some(minutes))
            }
        }
    }

    private func binding(at index: Int) -> Binding<Int?> {
        Binding {
            index < alerts.count ? alerts[index] : nil
        } set: { value in
            if let value {
                if index < alerts.count { alerts[index] = value } else { alerts.append(value) }
            } else if index < alerts.count {
                alerts.remove(at: index)
            }
        }
    }
}
