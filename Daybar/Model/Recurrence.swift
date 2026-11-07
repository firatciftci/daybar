import EventKit
import Foundation

struct RepeatRule: Equatable {
    enum End: Hashable {
        case never
        case date
        case count
    }

    static let frequencies: Array<EKRecurrenceFrequency> = [.daily, .weekly, .monthly, .yearly]

    var frequency: EKRecurrenceFrequency
    var interval = 1
    var weekdays: Set<Int> = []
    var byWeekday = false
    var end = End.never
    var endDate: Date
    var count = 10

    init(frequency: EKRecurrenceFrequency, start: Date) {
        self.frequency = frequency
        endDate = start.adding(months: 3)
        if frequency == .weekly { weekdays = [Self.weekday(of: start)] }
    }

    init(rule: EKRecurrenceRule, start: Date) {
        self.init(frequency: rule.frequency, start: start)
        interval = max(1, rule.interval)
        let days = rule.daysOfTheWeek ?? []
        if frequency == .weekly, !days.isEmpty { weekdays = Set(days.map(\.dayOfTheWeek.rawValue)) }
        byWeekday = frequency == .monthly && (days.contains { $0.weekNumber != 0 } || rule.setPositions?.isEmpty == false)
        if let finish = rule.recurrenceEnd {
            if let date = finish.endDate {
                end = .date
                endDate = date
            } else {
                end = .count
                count = max(1, finish.occurrenceCount)
            }
        }
    }

    func make(start: Date) -> EKRecurrenceRule {
        var days: Array<EKRecurrenceDayOfWeek>?
        if frequency == .weekly, !weekdays.isEmpty {
            days = weekdays.sorted().compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
        } else if frequency == .monthly, byWeekday, let day = EKWeekday(rawValue: Self.weekday(of: start)) {
            days = [EKRecurrenceDayOfWeek(day, weekNumber: Self.position(of: start))]
        }
        let finish: EKRecurrenceEnd? =
            switch end {
            case .never: nil
            case .date: EKRecurrenceEnd(end: endDate.startOfDay.adding(days: 1).addingTimeInterval(-1))
            case .count: EKRecurrenceEnd(occurrenceCount: count)
            }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: interval, daysOfTheWeek: days, daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: finish)
    }

    func summary(start: Date) -> String {
        let base = Self.every(frequency, interval)
        var text = base
        if frequency == .weekly, !weekdays.isEmpty, weekdays != [Self.weekday(of: start)] {
            let names = Self.ordered(weekdays).map { Calendar.daybar.standaloneWeekdaySymbols[$0 - 1] }
            text = L.repeatOnDays(base, names.formatted(.list(type: .and)))
        } else if frequency == .monthly {
            text =
                byWeekday
                ? L.repeatOnWeekday(base, Self.ordinalWord(of: start), Self.weekdayName(of: start))
                : L.repeatOnDate(base, Self.ordinalDay(of: start))
        }
        switch end {
        case .never: return text
        case .date: return L.repeatUntil(text, endDate.formatted(date: .abbreviated, time: .omitted))
        case .count: return L.repeatTimesSummary(text, count)
        }
    }

    static func summary(of event: EKEvent) -> String? {
        guard let rule = event.recurrenceRules?.first else { return nil }
        return Self(rule: rule, start: event.startDate).summary(start: event.startDate)
    }

    static func title(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: L.frequencyDaily
        case .weekly: L.frequencyWeekly
        case .monthly: L.frequencyMonthly
        case .yearly: L.frequencyYearly
        @unknown default: L.repeatCustom
        }
    }

    static func every(_ frequency: EKRecurrenceFrequency, _ interval: Int) -> String {
        switch frequency {
        case .daily: L.repeatEveryDays(interval)
        case .weekly: L.repeatEveryWeeks(interval)
        case .monthly: L.repeatEveryMonths(interval)
        case .yearly: L.repeatEveryYears(interval)
        @unknown default: L.repeatCustom
        }
    }

    static func weekday(of date: Date) -> Int {
        Calendar.daybar.component(.weekday, from: date)
    }

    static func ordered(_ days: some Collection<Int>) -> Array<Int> {
        let first = Calendar.daybar.firstWeekday
        return days.sorted { ($0 - first + 7) % 7 < ($1 - first + 7) % 7 }
    }

    static func weekdayName(of date: Date) -> String {
        Calendar.daybar.standaloneWeekdaySymbols[weekday(of: date) - 1]
    }

    static func ordinalDay(of date: Date) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let day = Calendar.daybar.component(.day, from: date)
        return formatter.string(for: day) ?? "\(day)"
    }

    static func ordinalWord(of date: Date) -> String {
        let position = position(of: date)
        return position < 0 ? L.ordinalLast : L.ordinalWords[position - 1]
    }

    private static func position(of date: Date) -> Int {
        let ordinal = Calendar.daybar.component(.weekdayOrdinal, from: date)
        return ordinal > L.ordinalWords.count ? -1 : ordinal
    }
}

enum AlertOffset {
    static let timedPresets = [0, 5, 10, 15, 30, 60, 120, 1_440, 2_880, 10_080]
    static let allDayPresets = [-540, 900, 2_340, 9_540]

    static func minutes(of alarm: EKAlarm) -> Int {
        Int((-alarm.relativeOffset / 60).rounded())
    }

    static func relative(_ alarms: Array<EKAlarm>?) -> Array<EKAlarm> {
        (alarms ?? []).filter { $0.absoluteDate == nil && $0.structuredLocation == nil }
    }

    static func options(including current: Int?, allDay: Bool) -> Array<Int> {
        var values = allDay ? allDayPresets : timedPresets
        if let current, !values.contains(current) { values.append(current) }
        return values.sorted()
    }

    static func title(_ minutes: Int, allDay: Bool) -> String {
        if allDay, minutes > -1_440 {
            let days = max(0, Int((Double(minutes) / 1_440).rounded(.up)))
            let time = Fmt.time(Date.now.startOfDay.addingTimeInterval(TimeInterval((days * 1_440 - minutes) * 60)))
            return days == 0 ? L.alertOnDay(time) : L.alertDaysBefore(duration(days * 1_440), time)
        }
        if minutes == 0 { return L.alertAtTime }
        return minutes > 0 ? L.alertBefore(duration(minutes)) : L.alertAfter(duration(-minutes))
    }

    private static func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.weeks, .days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
    }
}
