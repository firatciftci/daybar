import Foundation

extension Calendar {
    static var daybar: Self {
        var calendar = Self.autoupdatingCurrent
        let weekStart = Preferences.shared.weekStart
        if weekStart != 0 {
            calendar.firstWeekday = weekStart
        }
        return calendar
    }
}

extension Date {
    var startOfDay: Date { Calendar.daybar.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.daybar.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        Calendar.daybar.date(byAdding: .month, value: months, to: self) ?? self
    }

    var startOfMonth: Date {
        let calendar = Calendar.daybar
        return calendar.date(from: calendar.dateComponents([.year, .month], from: self)) ?? self
    }

    var startOfWeek: Date {
        let calendar = Calendar.daybar
        return calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.daybar.isDate(self, inSameDayAs: other)
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.daybar.isDate(self, equalTo: other, toGranularity: .month)
    }

    var isToday: Bool { Calendar.daybar.isDateInToday(self) }

    var dayNumber: Int { Calendar.daybar.component(.day, from: self) }

    var minutesIntoDay: Double {
        timeIntervalSince(startOfDay) / 60
    }
}

enum Fmt {
    static func time(_ date: Date, in zone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    static func shortHour(_ date: Date, in zone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = zone
        return date.formatted(style)
    }

    static func timeRange(_ start: Date, _ end: Date, in zone: TimeZone = .autoupdatingCurrent) -> String {
        guard end > start else { return time(start, in: zone) }
        var style = Date.IntervalFormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return (start..<end).formatted(style)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        let duration = Duration.seconds(minutes * 60)
        return duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    static func year(_ date: Date) -> String {
        date.formatted(.dateTime.year())
    }

    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func mediumDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func relativeDayName(_ date: Date) -> String? {
        let calendar = Calendar.daybar
        if calendar.isDateInToday(date) { return L.today }
        if calendar.isDateInTomorrow(date) { return L.tomorrow }
        if calendar.isDateInYesterday(date) { return L.yesterday }
        return nil
    }

    static func dayHeadline(_ date: Date) -> String {
        relativeDayName(date) ?? date.formatted(.dateTime.weekday(.wide))
    }

    static func daySubline(_ date: Date) -> String {
        if relativeDayName(date) != nil {
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        let calendar = Calendar.daybar
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    static func compactDay(_ date: Date) -> String {
        if let name = relativeDayName(date) { return name }
        return mediumDay(date)
    }

    static func gapRange(_ start: Date, _ end: Date) -> String {
        if start.isSameDay(as: end) {
            return mediumDay(start)
        }
        return (start..<end).formatted(.interval.month(.abbreviated).day())
    }

    static func zoneName(_ zone: TimeZone) -> String {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        return city ?? zone.identifier
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
