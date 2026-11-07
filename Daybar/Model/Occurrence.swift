import EventKit
import SwiftUI

struct Occurrence: Identifiable, Hashable {
    let id: String
    let eventIdentifier: String
    let externalIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarID: String
    let calendarTitle: String
    let location: String?
    let meeting: MeetingLink?
    let isDeclined: Bool
    let isPendingInvite: Bool
    let isRecurring: Bool
    let birthday: Birthday?
    let searchText: String

    init(_ event: EKEvent) {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        eventIdentifier = identifier
        externalIdentifier = event.calendarItemExternalIdentifier
        start = event.startDate
        end = max(event.endDate, event.startDate)
        id = "\(identifier)|\(start.timeIntervalSinceReferenceDate)"
        title = event.title?.isEmpty == false ? event.title : L.newEventTitle
        isAllDay = event.isAllDay
        color = event.calendar.map { Color(nsColor: $0.color) } ?? .gray
        calendarID = event.calendar?.calendarIdentifier ?? ""
        calendarTitle = event.calendar?.title ?? ""
        let place = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = MeetingLink.detect(in: [event.url?.absoluteString, place, event.notes])
        meeting = link
        if let place, place.contains(where: { $0.isLetter || $0.isNumber }), !(link.map { place.contains($0.url.host ?? "\u{0}") } ?? false)
        {
            location = place
        } else {
            location = nil
        }
        let me = event.attendees?.first(where: \.isCurrentUser)
        isDeclined = me?.participantStatus == .declined
        isPendingInvite = me?.participantStatus == .pending
        isRecurring = event.hasRecurrenceRules
        birthday = Birthday(event, title: title)
        searchText = [event.title, event.location, event.notes, event.calendar?.title]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var spannedDays: Array<Date> {
        let first = start.startOfDay
        let lastMoment = end > start ? end.addingTimeInterval(-1) : end
        let last = lastMoment.startOfDay
        var result: Array<Date> = [first]
        var cursor = first
        while cursor < last, result.count < 62 {
            cursor = cursor.adding(days: 1)
            result.append(cursor)
        }
        return result
    }

    func isLive(at date: Date = .now) -> Bool {
        !isAllDay && start <= date && date < end
    }

    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    var spansMultipleDays: Bool { spannedDays.count > 1 }

    func fills(_ day: Date) -> Bool {
        if isAllDay { return true }
        guard spansMultipleDays else { return false }
        return start < day.startOfDay && end >= day.startOfDay.adding(days: 1)
    }

    static func order(_ a: Self, _ b: Self) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.end != b.end { return a.end > b.end }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

struct Birthday: Hashable {
    let name: String
    let age: Int?
    let contactID: String?
    let contactURL: URL?

    init?(_ event: EKEvent, title: String) {
        let fromContacts = event.calendar?.type == .birthday || event.birthdayContactIdentifier != nil
        let match = title.wholeMatch(of: /(.+?)[’'‘]s?\s+(?:(\d+)(?:st|nd|rd|th)\s+)?birthday/.ignoresCase())
        guard fromContacts || (event.isAllDay && match != nil) else { return nil }
        name = match.map { String($0.1).trimmingCharacters(in: .whitespaces) } ?? title
        age = match?.2.flatMap { Int($0) }
        contactURL = event.url.flatMap { $0.scheme == "addressbook" ? $0 : nil }
        contactID =
            event.birthdayContactIdentifier ?? contactURL.map { $0.absoluteString.replacingOccurrences(of: "addressbook://", with: "") }
    }

    var key: String { name.lowercased() }

    func ageLine(on date: Date) -> String {
        guard let age else { return L.birthday }
        return date < Date().startOfDay ? L.turnedAge(age) : L.turnsAge(age)
    }
}

nonisolated struct ReminderItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let due: Date
    let hasTime: Bool
    let color: Color
    let listTitle: String

    init?(_ reminder: EKReminder) {
        guard let components = reminder.dueDateComponents,
            let due = Calendar.current.date(from: components)
        else { return nil }
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? ""
        self.due = due
        hasTime = components.hour != nil
        color = Color(cgColor: reminder.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
        listTitle = reminder.calendar?.title ?? ""
    }

    var sortMoment: Date { hasTime ? due : Calendar.current.startOfDay(for: due) }
}
