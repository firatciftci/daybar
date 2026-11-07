import Foundation
import Observation

enum PanelMode: String, CaseIterable, Identifiable, Codable {
    case month
    case week
    case day
    case upNext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: L.viewMonth
        case .week: L.viewWeek
        case .day: L.viewDay
        case .upNext: L.viewUpNext
        }
    }

    var symbol: String {
        switch self {
        case .month: "calendar"
        case .week: "list.bullet.below.rectangle"
        case .day: "calendar.day.timeline.left"
        case .upNext: "clock"
        }
    }
}

struct CalendarSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var calendarIDs: Set<String>
}

struct WeatherPlace: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var defaultView = PanelMode.month { didSet { store(defaultView.rawValue, "defaultView") } }
    var weekStart = 0 { didSet { store(weekStart, "weekStart") } }
    var showWeekNumbers = false { didSet { store(showWeekNumbers, "showWeekNumbers") } }
    var secondTimeZoneID: String? { didSet { store(secondTimeZoneID, "secondTimeZoneID") } }
    var showMeetingIcon = true { didSet { store(showMeetingIcon, "showMeetingIcon") } }
    var meetingLeadMinutes = 10 { didSet { store(meetingLeadMinutes, "meetingLeadMinutes") } }
    var showNextEvent = true { didSet { store(showNextEvent, "showNextEvent") } }
    var nextEventMinutes = 60 { didSet { store(nextEventMinutes, "nextEventMinutes") } }
    var showDeclined = false { didSet { store(showDeclined, "showDeclined") } }
    var showReminders = true { didSet { store(showReminders, "showReminders") } }
    var defaultCalendarID: String? { didSet { store(defaultCalendarID, "defaultCalendarID") } }
    var focusCalendarIDs: Set<String>?
    var hiddenCalendarIDs: Set<String> = [] { didSet { encode(hiddenCalendarIDs, "hiddenCalendarIDs") } }
    var calendarSets: Array<CalendarSet> = [] { didSet { encode(calendarSets, "calendarSets") } }
    var activeSetID: UUID? { didSet { store(activeSetID?.uuidString, "activeSetID") } }
    var showWeather = true { didSet { store(showWeather, "showWeather") } }
    var useCurrentLocation = true { didSet { store(useCurrentLocation, "useCurrentLocation") } }
    var weatherPlace: WeatherPlace? { didSet { encode(weatherPlace, "weatherPlace") } }
    var compact = false { didSet { store(compact, "compact") } }
    var showQuickAdd = true { didSet { store(showQuickAdd, "showQuickAdd") } }
    var separateAllDay = false { didSet { store(separateAllDay, "separateAllDay") } }
    var remindersByTime = false { didSet { store(remindersByTime, "remindersByTime") } }
    var hasOnboarded = false { didSet { store(hasOnboarded, "hasOnboarded") } }
    var panelHeight = 0.0 { didSet { store(panelHeight, "panelHeight") } }

    @ObservationIgnored private var loading = false

    private static let keptKeys: Set<String> = ["calendarSets", "hasOnboarded"]
    private static let keys = [
        "defaultView", "weekStart", "showWeekNumbers", "secondTimeZoneID", "showMeetingIcon", "meetingLeadMinutes", "showNextEvent",
        "nextEventMinutes", "showDeclined",
        "showReminders", "defaultCalendarID", "hiddenCalendarIDs", "calendarSets", "activeSetID", "showWeather", "useCurrentLocation",
        "weatherPlace", "compact", "showQuickAdd", "separateAllDay", "remindersByTime", "hasOnboarded", "panelHeight", "hiddenMeetingIDs",
    ]

    private init() {
        load()
    }

    func restoreDefaults() {
        for key in Self.keys where !Self.keptKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        load()
    }

    private func load() {
        loading = true
        defer { loading = false }
        let d = defaults
        defaultView = d.string(forKey: "defaultView").flatMap(PanelMode.init(rawValue:)) ?? .month
        weekStart = d.integer(forKey: "weekStart")
        showWeekNumbers = d.bool(forKey: "showWeekNumbers")
        secondTimeZoneID = d.string(forKey: "secondTimeZoneID")
        showMeetingIcon = d.object(forKey: "showMeetingIcon") as? Bool ?? true
        meetingLeadMinutes = d.object(forKey: "meetingLeadMinutes") as? Int ?? 10
        showNextEvent = d.object(forKey: "showNextEvent") as? Bool ?? true
        nextEventMinutes = d.object(forKey: "nextEventMinutes") as? Int ?? 60
        showDeclined = d.bool(forKey: "showDeclined")
        showReminders = d.object(forKey: "showReminders") as? Bool ?? true
        defaultCalendarID = d.string(forKey: "defaultCalendarID")
        hiddenCalendarIDs = Self.decode(Set<String>.self, d, "hiddenCalendarIDs") ?? []
        calendarSets = Self.decode(Array<CalendarSet>.self, d, "calendarSets") ?? []
        activeSetID = d.string(forKey: "activeSetID").flatMap(UUID.init(uuidString:))
        showWeather = d.object(forKey: "showWeather") as? Bool ?? true
        useCurrentLocation = d.object(forKey: "useCurrentLocation") as? Bool ?? true
        weatherPlace = Self.decode(WeatherPlace.self, d, "weatherPlace")
        compact = d.bool(forKey: "compact")
        showQuickAdd = d.object(forKey: "showQuickAdd") as? Bool ?? true
        separateAllDay = d.bool(forKey: "separateAllDay")
        remindersByTime = d.bool(forKey: "remindersByTime")
        hasOnboarded = d.bool(forKey: "hasOnboarded")
        panelHeight = d.double(forKey: "panelHeight")
    }

    var secondTimeZone: TimeZone? {
        secondTimeZoneID.flatMap(TimeZone.init(identifier:))
    }

    var activeSet: CalendarSet? {
        guard let activeSetID else { return nil }
        return calendarSets.first { $0.id == activeSetID }
    }

    func isCalendarVisible(_ id: String) -> Bool {
        if let focusCalendarIDs { return focusCalendarIDs.contains(id) }
        if let activeSet { return activeSet.calendarIDs.contains(id) }
        return !hiddenCalendarIDs.contains(id)
    }

    func toggleCalendar(_ id: String) {
        if let activeSet, let index = calendarSets.firstIndex(of: activeSet) {
            if calendarSets[index].calendarIDs.contains(id) {
                calendarSets[index].calendarIDs.remove(id)
            } else {
                calendarSets[index].calendarIDs.insert(id)
            }
            return
        }
        if hiddenCalendarIDs.contains(id) {
            hiddenCalendarIDs.remove(id)
        } else {
            hiddenCalendarIDs.insert(id)
        }
    }

    private func store(_ value: Any?, _ key: String) {
        guard !loading else { return }
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard !loading else { return }
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
