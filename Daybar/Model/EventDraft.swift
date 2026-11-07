import EventKit
import Foundation

enum RecurrenceChoice: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: L.repeatNever
        case .daily: L.repeatDaily
        case .weekly: L.repeatWeekly
        case .monthly: L.repeatMonthly
        case .yearly: L.repeatYearly
        case .custom: L.repeatCustom
        }
    }

    var frequency: EKRecurrenceFrequency? {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        case .never, .custom: nil
        }
    }

    init(rules: Array<EKRecurrenceRule>?) {
        guard let rules, !rules.isEmpty else {
            self = .never
            return
        }
        guard rules.count == 1, let rule = rules.first, rule.interval == 1,
            rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
            rule.setPositions == nil, rule.recurrenceEnd == nil
        else {
            self = .custom
            return
        }
        switch rule.frequency {
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        @unknown default: self = .custom
        }
    }
}

struct EventDraft: Equatable {
    var id = UUID()
    var occurrence: Occurrence?
    var title = ""
    var location = ""
    var isAllDay: Bool
    var start: Date
    var end: Date
    var calendarID: String
    var recurrence = RecurrenceChoice.never
    var repeatRule: RepeatRule
    var alerts: Array<Int> = []
    var url = ""
    var notes = ""
    var notesBaseline = ""
    var wasRecurring = false
    private var recurrenceBaseline = RecurrenceChoice.never
    private var repeatBaseline: RepeatRule
    private var alertsBaseline: Array<Int> = []

    var isNew: Bool { occurrence == nil }

    static func new(start: Date, end: Date, allDay: Bool) -> Self {
        Self(start: start, end: end, allDay: allDay)
    }

    private init(start: Date, end: Date, allDay: Bool) {
        isAllDay = allDay
        self.start = start
        self.end = end
        calendarID = CalendarStore.shared.defaultCalendar?.calendarIdentifier ?? ""
        repeatRule = RepeatRule(frequency: .weekly, start: start)
        repeatBaseline = repeatRule
    }

    init(event: EKEvent, occurrence: Occurrence) {
        self.init(
            start: event.startDate, end: event.isAllDay ? event.endDate.addingTimeInterval(-1) : event.endDate,
            allDay: event.isAllDay)
        self.occurrence = occurrence
        title = event.title ?? ""
        location = event.location ?? ""
        calendarID = event.calendar?.calendarIdentifier ?? ""
        recurrence = RecurrenceChoice(rules: event.recurrenceRules)
        if let rule = event.recurrenceRules?.first { repeatRule = RepeatRule(rule: rule, start: start) }
        recurrenceBaseline = recurrence
        repeatBaseline = repeatRule
        alerts = AlertOffset.relative(event.alarms).map(AlertOffset.minutes)
        alertsBaseline = alerts
        url = event.url?.absoluteString ?? ""
        notes = (event.notes ?? "").plainNotes
        notesBaseline = notes
        wasRecurring = event.hasRecurrenceRules
    }

    mutating func choose(_ choice: RecurrenceChoice) {
        if choice == .custom, recurrence != .custom {
            repeatRule =
                recurrenceBaseline == .custom ? repeatBaseline : RepeatRule(frequency: recurrence.frequency ?? .weekly, start: start)
        }
        recurrence = choice
    }

    func apply(to event: EKEvent, store: CalendarStore) {
        event.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? L.newEventTitle : title
        event.location = location.isEmpty ? nil : location
        event.isAllDay = isAllDay
        if isAllDay {
            event.startDate = start.startOfDay
            event.endDate = max(end, start).startOfDay.adding(days: 1).addingTimeInterval(-1)
        } else {
            event.startDate = start
            event.endDate = max(end, start)
        }
        if let calendar = store.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        }
        if recurrence != recurrenceBaseline || (recurrence == .custom && repeatRule != repeatBaseline) {
            for rule in event.recurrenceRules ?? [] {
                event.removeRecurrenceRule(rule)
            }
            if recurrence == .custom {
                event.addRecurrenceRule(repeatRule.make(start: start))
            } else if let frequency = recurrence.frequency {
                event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
            }
        }
        if alerts != alertsBaseline {
            for alarm in AlertOffset.relative(event.alarms) {
                event.removeAlarm(alarm)
            }
            for minutes in alerts {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
            }
        }
        event.url = URL(string: url.trimmingCharacters(in: .whitespaces)).flatMap { $0.scheme == nil ? nil : $0 }
        if notes != notesBaseline {
            event.notes = notes.isEmpty ? nil : notes
        }
    }
}

extension String {
    var plainNotes: String {
        var text = self
        if text.range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</li>"#, with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
                text = text.replacingOccurrences(of: entity, with: character)
            }
        }
        text = text.replacingOccurrences(of: #"\n[ \t]*\n(\s*\n)+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
