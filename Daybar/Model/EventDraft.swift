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
            rule.setPositions == nil
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

enum AlertChoice: Int, CaseIterable, Identifiable {
    case off = -1
    case atTime = 0
    case five = 5
    case fifteen = 15
    case thirty = 30
    case hour = 60
    case day = 1_440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: L.alertNone
        case .atTime: L.alertAtTime
        case .five, .fifteen, .thirty: L.alertMinutes(rawValue)
        case .hour: L.alertHour
        case .day: L.alertDay
        }
    }

    init(alarms: Array<EKAlarm>?) {
        guard let offset = alarms?.first?.relativeOffset else {
            self = .off
            return
        }
        let minutes = Int((-offset / 60).rounded())
        self = Self(rawValue: minutes) ?? .fifteen
    }
}

struct EventDraft: Equatable {
    var id = UUID()
    var occurrence: Occurrence?
    var title: String
    var location: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    var calendarID: String
    var recurrence: RecurrenceChoice
    var alert: AlertChoice
    var url: String
    var notes: String
    var notesBaseline = ""
    var wasRecurring: Bool

    var isNew: Bool { occurrence == nil }

    static func new(start: Date, end: Date, allDay: Bool) -> Self {
        Self(
            occurrence: nil,
            title: "",
            location: "",
            isAllDay: allDay,
            start: start,
            end: end,
            calendarID: CalendarStore.shared.defaultCalendar?.calendarIdentifier ?? "",
            recurrence: .never,
            alert: .off,
            url: "",
            notes: "",
            wasRecurring: false
        )
    }

    init(
        occurrence: Occurrence?, title: String, location: String, isAllDay: Bool, start: Date, end: Date,
        calendarID: String, recurrence: RecurrenceChoice, alert: AlertChoice, url: String, notes: String, wasRecurring: Bool
    ) {
        self.occurrence = occurrence
        self.title = title
        self.location = location
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.recurrence = recurrence
        self.alert = alert
        self.url = url
        self.notes = notes
        self.wasRecurring = wasRecurring
    }

    init(event: EKEvent, occurrence: Occurrence) {
        self.occurrence = occurrence
        title = event.title ?? ""
        location = event.location ?? ""
        isAllDay = event.isAllDay
        start = event.startDate
        end = event.isAllDay ? event.endDate.addingTimeInterval(-1) : event.endDate
        calendarID = event.calendar?.calendarIdentifier ?? ""
        recurrence = RecurrenceChoice(rules: event.recurrenceRules)
        alert = AlertChoice(alarms: event.alarms)
        url = event.url?.absoluteString ?? ""
        notes = (event.notes ?? "").plainNotes
        notesBaseline = notes
        wasRecurring = event.hasRecurrenceRules
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
        if let calendar = store.ek.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        }
        if recurrence != .custom {
            for rule in event.recurrenceRules ?? [] {
                event.removeRecurrenceRule(rule)
            }
            if let frequency = recurrence.frequency {
                event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
            }
        }
        if alert != AlertChoice(alarms: event.alarms) || event.alarms == nil {
            for alarm in event.alarms ?? [] {
                event.removeAlarm(alarm)
            }
            if alert != .off {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alert.rawValue * 60)))
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
