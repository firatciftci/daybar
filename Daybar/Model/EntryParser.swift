import EventKit
import Foundation

struct ParsedEntry {
    enum Kind {
        case event
        case reminder
    }

    var kind: Kind = .event
    var title = ""
    var start: Date?
    var end: Date?
    var hasTime = false
    var isAllDay = false
    var location: String?
    var calendar: EKCalendar?
    var reminderList: EKCalendar?
    var alertMinutes: Int?
    var recurrence: EKRecurrenceFrequency?

    var isEmpty: Bool { title.isEmpty }

    func apply(to event: EKEvent) {
        event.title = title
        let begin = start ?? EntryParser.nextSlot()
        event.isAllDay = isAllDay
        event.startDate = begin
        event.endDate = end ?? begin.addingTimeInterval(isAllDay ? 86_400 : 3_600)
        if let location { event.location = location }
        if let alertMinutes { event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMinutes * 60))) }
        if let recurrence {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: recurrence, interval: 1, end: nil))
        }
    }
}

enum EntryParser {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let reminderPrefix = regex(#"^(?:remind\s+me\s+to|remind\s+me|remind|todo|to-do|task)\b[:\s]*"#)
    private static let calendarTag = regex(#"(?:^|\s)/(\S+)"#)
    private static let alertPattern = regex(
        #"\b(?:alert|alarm|remind(?:\s+me)?)\s+(\d+)\s*(m|min|mins|minutes?|h|hr|hrs|hours?)\b(?:\s+(?:before|ahead|early))?"#)
    private static let everyWeekday = regex(#"\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
    private static let recurrencePattern = regex(
        #"\b(every\s+day|daily|every\s+week|weekly|every\s+month|monthly|every\s+year|yearly|annually)\b"#)
    private static let durationPattern = regex(#"\bfor\s+(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?)\b"#)
    private static let timePattern = regex(
        #"(\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.))|(\d{1,2}:\d{2})|\bnoon\b|\bmidnight\b|\btonight\b|\bat\s+\d{1,2}\b"#)
    private static let locationPattern = regex(#"\s(?:at|@)\s+(.+)$"#)
    private static let danglingWords = regex(#"(?:\s+|^)(?:on|at|from|for|by|,|-)\s*$"#)
    private static let leadingPreposition = regex(#"(?:^|\s)(?:on|at|from|by)\s+$"#)

    static func nextSlot(after date: Date = .now) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? date
    }

    static func parse(_ raw: String, calendars: Array<EKCalendar>, reminderLists: Array<EKCalendar>, now: Date = .now) -> ParsedEntry {
        var entry = ParsedEntry()
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return entry }

        if let match = first(reminderPrefix, in: text) {
            entry.kind = .reminder
            text = remove(match.range, from: text)
        }

        if let match = first(calendarTag, in: text), let token = substring(match.range(at: 1), in: text) {
            let needle = token.lowercased()
            let pool = entry.kind == .reminder ? reminderLists : calendars.filter(\.allowsContentModifications)
            let found =
                pool.first { $0.title.lowercased() == needle }
                ?? pool.first { $0.title.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(needle) }
            if let found {
                if entry.kind == .reminder { entry.reminderList = found } else { entry.calendar = found }
                text = remove(match.range, from: text)
            }
        }

        if let match = first(alertPattern, in: text),
            let amount = substring(match.range(at: 1), in: text).flatMap(Int.init),
            let unit = substring(match.range(at: 2), in: text)?.lowercased()
        {
            entry.alertMinutes = unit.hasPrefix("h") ? amount * 60 : amount
            text = remove(match.range, from: text)
        }

        if let match = first(everyWeekday, in: text), let day = substring(match.range(at: 1), in: text) {
            entry.recurrence = .weekly
            text = replace(match.range, in: text, with: "on \(day)")
        } else if let match = first(recurrencePattern, in: text), let word = substring(match.range(at: 1), in: text)?.lowercased() {
            entry.recurrence = recurrence(for: word)
            text = remove(match.range, from: text)
        }

        var explicitDuration: TimeInterval?
        if let match = first(durationPattern, in: text),
            let amount = substring(match.range(at: 1), in: text).flatMap(Double.init),
            let unit = substring(match.range(at: 2), in: text)?.lowercased()
        {
            explicitDuration = unit.hasPrefix("h") ? amount * 3_600 : amount * 60
            text = remove(match.range, from: text)
        }

        applyDate(to: &entry, text: &text, explicitDuration: explicitDuration)

        if entry.start == nil, entry.kind == .event {
            let begin = nextSlot(after: now)
            entry.start = begin
            entry.end = begin.addingTimeInterval(explicitDuration ?? 3_600)
            entry.hasTime = true
        }

        if let match = first(locationPattern, in: text), let place = substring(match.range(at: 1), in: text) {
            entry.location = place.trimmingCharacters(in: .whitespaces)
            text = remove(match.range, from: text)
        }

        while let match = first(danglingWords, in: text) {
            text = remove(match.range, from: text)
        }

        entry.title =
            text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-"))
        return entry
    }

    private static func recurrence(for word: String) -> EKRecurrenceFrequency {
        if word.contains("day") || word == "daily" { return .daily }
        if word.contains("week") { return .weekly }
        if word.contains("month") { return .monthly }
        return .yearly
    }

    private static func applyDate(to entry: inout ParsedEntry, text: inout String, explicitDuration: TimeInterval?) {
        guard let detector,
            let match = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).first,
            let date = match.date,
            let matched = substring(match.range, in: text)
        else { return }
        entry.hasTime = first(timePattern, in: matched) != nil
        let detected = match.duration > 0 ? match.duration : nil
        if entry.hasTime {
            entry.start = date
            entry.end = date.addingTimeInterval(explicitDuration ?? detected ?? 3_600)
        } else {
            let day = Calendar.current.startOfDay(for: date)
            entry.start = day
            entry.isAllDay = entry.kind == .event
            let length = max(1, Int(((explicitDuration ?? 0) / 86_400).rounded(.up)))
            entry.end = Calendar.current.date(byAdding: .day, value: length, to: day)
        }
        text = remove(withPreposition(match.range, in: text), from: text)
    }

    private static func first(_ regex: NSRegularExpression?, in text: String) -> NSTextCheckingResult? {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ range: NSRange, in text: String) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func withPreposition(_ range: NSRange, in text: String) -> NSRange {
        guard let head = Range(NSRange(location: 0, length: range.location), in: text) else { return range }
        let prefix = String(text[head])
        guard let match = first(leadingPreposition, in: prefix) else { return range }
        return NSRange(location: match.range.location, length: NSMaxRange(range) - match.range.location)
    }

    private static func remove(_ range: NSRange, from text: String) -> String {
        replace(range, in: text, with: " ")
    }

    private static func replace(_ range: NSRange, in text: String, with replacement: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var copy = text
        copy.replaceSubrange(swiftRange, with: replacement)
        return copy
    }
}
