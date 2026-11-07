import AppKit
import EventKit

final class DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demo")

    static let appearance: NSAppearance.Name? = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-dark") { return .darkAqua }
        if arguments.contains("-light") { return .aqua }
        return nil
    }()

    static let defaults: UserDefaults = {
        let name = "com.firatciftci.Daybar.demo"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        defaults.register(defaults: ["hasOnboarded": true, "useCurrentLocation": false])
        return defaults
    }()

    private(set) var calendars: Array<EKCalendar> = []
    private(set) var lists: Array<EKCalendar> = []
    private(set) var events: Array<EKEvent> = []
    private(set) var reminders: Array<EKReminder> = []
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
        let work = calendar("Work", 0x1BADF8)
        let home = calendar("Home", 0x63DA38)
        let family = calendar("Family", 0xFF9500)
        let fitness = calendar("Fitness", 0xFF2968)
        let travel = calendar("Travel", 0xCC73E1)
        let birthdays = calendar("Birthdays", 0xA2845E)
        calendars = [work, home, family, fitness, travel, birthdays]

        let today = Date().startOfDay
        for offset in -42...56 {
            let day = today.adding(days: offset)
            switch Calendar.current.component(.weekday, from: day) {
            case 1:
                add("Family dinner", family, day, 18, 2, location: "Grandma’s", repeats: .weekly)
            case 2:
                add("Standup", work, day, 9.5, 0.25, url: "https://meet.google.com/abc-defg-hij", repeats: .daily)
                add("Planning", work, day, 11, 1, location: "Studio B", repeats: .weekly)
            case 3, 5:
                add("Standup", work, day, 9.5, 0.25, url: "https://meet.google.com/abc-defg-hij", repeats: .daily)
                add("Run club", fitness, day, 7, 1, location: "Lakeside Park", rule: runClub)
                if Calendar.current.component(.weekday, from: day) == 5, ((offset + 700) / 7).isMultiple(of: 2) {
                    add(
                        "Design review", work, day, 14, 1, location: "Studio B", url: "https://zoom.us/j/5551234567",
                        notes: "Walk through the new onboarding flow and agree on what ships first.", alerts: [10, 1_440])
                }
            case 4:
                add("Standup", work, day, 9.5, 0.25, url: "https://meet.google.com/abc-defg-hij", repeats: .daily)
                add("1:1 with Maya", work, day, 15, 0.5, url: "https://zoom.us/j/5559876543", repeats: .weekly)
            case 6:
                add("Standup", work, day, 9.5, 0.25, url: "https://meet.google.com/abc-defg-hij", repeats: .daily)
                add("Lunch with Sam", home, day, 12.5, 1, location: "Café Luna")
            default:
                add("Farmers market", home, day, 10, 1, location: "Ferry Plaza", repeats: .weekly)
            }
        }

        let now = Date()
        let quarter = TimeInterval(15 * 60)
        let next = Date(timeIntervalSinceReferenceDate: ((now.timeIntervalSinceReferenceDate + 5 * 60) / quarter).rounded(.up) * quarter)
        event("Climbing with Leo", fitness, next.addingTimeInterval(-9_000), next.addingTimeInterval(-3_600), location: "Mission Cliffs")
        event("Call with Mom", family, next, next.addingTimeInterval(1_800), url: "https://facetime.apple.com/join#v=1&p=demo")
        event("Movie night", home, next.addingTimeInterval(10_800), next.addingTimeInterval(19_800), location: "Rialto Cinema")

        allDay("Ana’s 30th birthday", birthdays, today.adding(days: 1))
        add("Dentist", home, today.adding(days: 3), 16, 1, location: "Bright Smile Dental", alerts: [60])
        add("Flight to Lisbon", travel, today.adding(days: 12), 18.5, 7, location: "SFO Terminal 2")
        allDay("Lisbon", travel, today.adding(days: 13), days: 5)
        add("Quarterly review", work, today.adding(days: 17), 10, 2, location: "Main Hall")
        add("Housewarming at Jo’s", home, today.adding(days: -6), 19, 3)
        allDay("Leo’s birthday", birthdays, today.adding(days: -11))
        add("Jazz in the park", home, today.adding(days: 22), 17, 2, location: "Golden Gate Bandshell")

        let errands = list("Errands", 0xFF9500)
        let personal = list("Personal", 0x1BADF8)
        lists = [errands, personal]
        remind("Renew passport", personal, today.adding(days: -2), hour: nil)
        remind("Pick up dry cleaning", errands, today, hour: 18)
        remind("Book the Lisbon hotel", personal, today.adding(days: 2), hour: nil)
    }

    static func forecasts() -> [Date: DayForecast] {
        let style = Measurement<UnitTemperature>.FormatStyle(
            width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        let conditions = [
            "sun.max.fill": "Sunny", "cloud.sun.fill": "Partly Cloudy", "cloud.fill": "Cloudy", "cloud.rain.fill": "Rain",
            "cloud.drizzle.fill": "Drizzle", "wind": "Windy",
        ]
        let days: Array<(symbol: String, high: Double)> = [
            ("sun.max.fill", 18), ("cloud.sun.fill", 16), ("cloud.fill", 14), ("cloud.rain.fill", 12), ("cloud.drizzle.fill", 13),
            ("cloud.sun.fill", 15), ("sun.max.fill", 19), ("sun.max.fill", 20), ("wind", 15), ("cloud.sun.fill", 17),
        ]
        var map: [Date: DayForecast] = [:]
        let today = Date().startOfDay
        for (index, day) in days.enumerated() {
            let date = today.adding(days: index)
            map[date] = DayForecast(
                date: date, symbolName: day.symbol,
                high: Measurement(value: day.high, unit: UnitTemperature.celsius).formatted(style),
                low: Measurement(value: day.high - 8, unit: UnitTemperature.celsius).formatted(style),
                condition: conditions[day.symbol] ?? "", precipitation: "\(index * 7 % 60)%", wind: nil, uvIndex: nil,
                sunrise: date.addingTimeInterval(6.8 * 3_600), sunset: date.addingTimeInterval(17 * 3_600))
        }
        return map
    }

    func insert(_ item: EKCalendarItem) {
        if let event = item as? EKEvent, !events.contains(where: { $0 === event }) { events.append(event) }
        if let reminder = item as? EKReminder, !reminders.contains(where: { $0 === reminder }) { reminders.append(reminder) }
    }

    func remove(_ item: EKCalendarItem) {
        events.removeAll { $0 === item }
        reminders.removeAll { $0 === item }
    }

    func item(withIdentifier identifier: String) -> EKCalendarItem? {
        events.first { $0.calendarItemIdentifier == identifier } ?? reminders.first { $0.calendarItemIdentifier == identifier }
    }

    func calendar(withIdentifier identifier: String) -> EKCalendar? {
        (calendars + lists).first { $0.calendarIdentifier == identifier }
    }

    private var runClub: EKRecurrenceRule {
        EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday), EKRecurrenceDayOfWeek(.thursday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    }

    private func calendar(_ title: String, _ hex: Int) -> EKCalendar {
        make(title, hex, EKCalendar(for: .event, eventStore: store))
    }

    private func list(_ title: String, _ hex: Int) -> EKCalendar {
        make(title, hex, EKCalendar(for: .reminder, eventStore: store))
    }

    private func make(_ title: String, _ hex: Int, _ calendar: EKCalendar) -> EKCalendar {
        calendar.title = title
        calendar.cgColor = CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        return calendar
    }

    private func add(
        _ title: String, _ calendar: EKCalendar, _ day: Date, _ hour: Double, _ hours: Double, location: String? = nil,
        url: String? = nil, notes: String? = nil, repeats: EKRecurrenceFrequency? = nil, rule: EKRecurrenceRule? = nil,
        alerts: Array<Int> = [10]
    ) {
        let start = day.addingTimeInterval(hour * 3_600)
        let event = self.event(title, calendar, start, start.addingTimeInterval(hours * 3_600), location: location, url: url, notes: notes)
        if let rule = rule ?? repeats.map({ EKRecurrenceRule(recurrenceWith: $0, interval: 1, end: nil) }) {
            event.addRecurrenceRule(rule)
        }
        for minutes in alerts {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
    }

    @discardableResult
    private func event(
        _ title: String, _ calendar: EKCalendar, _ start: Date, _ end: Date, location: String? = nil, url: String? = nil,
        notes: String? = nil
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.startDate = start
        event.endDate = end
        event.location = location
        event.url = url.flatMap(URL.init(string:))
        event.notes = notes
        events.append(event)
        return event
    }

    private func allDay(_ title: String, _ calendar: EKCalendar, _ day: Date, days: Int = 1) {
        let event = self.event(title, calendar, day, day.adding(days: days).addingTimeInterval(-1))
        event.isAllDay = true
    }

    private func remind(_ title: String, _ list: EKCalendar, _ day: Date, hour: Int?) {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = hour.map { _ in 0 }
        reminder.dueDateComponents = components
        reminders.append(reminder)
    }
}
