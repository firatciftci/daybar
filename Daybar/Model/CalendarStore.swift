import AppKit
import EventKit
import Observation

enum AccessState {
    case unknown
    case granted
    case denied
}

@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    @ObservationIgnored let ek = EKEventStore()
    @ObservationIgnored private let prefs = Preferences.shared

    private(set) var access: AccessState = .unknown
    private(set) var remindersGranted = false
    private(set) var eventCalendars: Array<EKCalendar> = []
    private(set) var reminderCalendars: Array<EKCalendar> = []
    private(set) var days: [Date: Array<Occurrence>] = [:]
    private(set) var reminders: [Date: Array<ReminderItem>] = [:]
    private(set) var overdueReminders: Array<ReminderItem> = []
    private(set) var range: DateInterval
    private(set) var revision = 0
    @ObservationIgnored private var observers: Array<any NSObjectProtocol> = []

    private init() {
        let today = Date().startOfDay
        range = DateInterval(start: today.adding(days: -150), end: today.adding(days: 400))
        refreshAccess()
        for (name, object) in [(Notification.Name.EKEventStoreChanged, ek as AnyObject?), (.NSCalendarDayChanged, nil)] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reload() }
                })
        }
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
        remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        reload()
    }

    func requestAccess() async {
        let events = (try? await ek.requestFullAccessToEvents()) ?? false
        if events {
            _ = try? await ek.requestFullAccessToReminders()
        }
        refreshAccess()
    }

    var visibleCalendars: Array<EKCalendar> {
        eventCalendars.filter { prefs.isCalendarVisible($0.calendarIdentifier) }
    }

    var calendarsBySource: Array<(source: String, calendars: Array<EKCalendar>)> {
        var order: Array<String> = []
        var groups: [String: Array<EKCalendar>] = [:]
        for calendar in eventCalendars {
            let title = calendar.source?.title ?? ""
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(calendar)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var writableCalendars: Array<EKCalendar> {
        eventCalendars.filter(\.allowsContentModifications)
    }

    var defaultCalendar: EKCalendar? {
        if let id = prefs.defaultCalendarID, let calendar = ek.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        return ek.defaultCalendarForNewEvents ?? writableCalendars.first
    }

    var defaultReminderList: EKCalendar? {
        ek.defaultCalendarForNewReminders()
    }

    func reload() {
        guard access == .granted else { return }
        eventCalendars = ek.calendars(for: .event).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        reminderCalendars = remindersGranted ? ek.calendars(for: .reminder) : []
        let visible = visibleCalendars
        var map: [Date: Array<Occurrence>] = [:]
        if !visible.isEmpty {
            let predicate = ek.predicateForEvents(withStart: range.start, end: range.end, calendars: visible)
            for event in ek.events(matching: predicate) {
                let occurrence = Occurrence(event)
                if occurrence.isDeclined, !prefs.showDeclined { continue }
                for day in occurrence.spannedDays {
                    map[day, default: []].append(occurrence)
                }
            }
        }
        for (key, list) in map {
            map[key] = Self.mergingBirthdays(list).sorted(by: Occurrence.order)
        }
        days = map
        revision += 1
        loadReminders()
    }

    private static func mergingBirthdays(_ list: Array<Occurrence>) -> Array<Occurrence> {
        var keep: [String: Occurrence] = [:]
        for occurrence in list {
            guard let birthday = occurrence.birthday else { continue }
            if let current = keep[birthday.key], current.birthday?.age != nil || birthday.age == nil { continue }
            keep[birthday.key] = occurrence
        }
        guard !keep.isEmpty else { return list }
        return list.filter { occurrence in
            guard let birthday = occurrence.birthday else { return true }
            return keep[birthday.key]?.id == occurrence.id
        }
    }

    func ensureLoaded(around date: Date) {
        let margin: TimeInterval = 45 * 86_400
        var next = range
        if date.timeIntervalSince(range.start) < margin {
            next = DateInterval(start: range.start.adding(days: -180), end: range.end)
        }
        if range.end.timeIntervalSince(date) < margin {
            next = DateInterval(start: next.start, end: next.end.adding(days: 365))
        }
        guard next != range else { return }
        range = next
        reload()
    }

    func occurrences(on day: Date) -> Array<Occurrence> {
        days[day.startOfDay] ?? []
    }

    func reminders(on day: Date) -> Array<ReminderItem> {
        guard prefs.showReminders else { return [] }
        let key = day.startOfDay
        var result = reminders[key] ?? []
        if key == Date().startOfDay {
            result = overdueReminders + result
        }
        return result
    }

    private func loadReminders() {
        guard remindersGranted, prefs.showReminders else {
            reminders = [:]
            overdueReminders = []
            return
        }
        let predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: range.end, calendars: nil)
        ek.fetchReminders(matching: predicate) { @Sendable [weak self] found in
            let items = (found ?? []).compactMap(ReminderItem.init)
            Task { @MainActor in self?.apply(items) }
        }
    }

    private func apply(_ items: Array<ReminderItem>) {
        let today = Date().startOfDay
        var map: [Date: Array<ReminderItem>] = [:]
        var overdue: Array<ReminderItem> = []
        for item in items {
            let day = item.due.startOfDay
            if day < today {
                overdue.append(item)
            } else {
                map[day, default: []].append(item)
            }
        }
        for key in map.keys {
            map[key]?.sort { $0.due < $1.due }
        }
        reminders = map
        overdueReminders = overdue.sorted { $0.due < $1.due }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = ek.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        guard (try? ek.save(reminder, commit: true)) != nil else { return }
        reload()
        EventHistory.shared.reminderCompleted(item.id)
    }

    func event(for occurrence: Occurrence) -> EKEvent? {
        event(identifier: occurrence.eventIdentifier, start: occurrence.start)
    }

    func event(identifier: String, start: Date) -> EKEvent? {
        let predicate = ek.predicateForEvents(withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(60), calendars: nil)
        let match = ek.events(matching: predicate).first {
            ($0.eventIdentifier ?? $0.calendarItemIdentifier) == identifier && $0.startDate == start
        }
        return match ?? ek.event(withIdentifier: identifier)
    }

    func newEvent() -> EKEvent {
        let event = EKEvent(eventStore: ek)
        event.calendar = defaultCalendar
        return event
    }

    @discardableResult
    func save(_ event: EKEvent, span: EKSpan = .thisEvent) -> Bool {
        do {
            try ek.save(event, span: span, commit: true)
            reload()
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    func delete(_ event: EKEvent, span: EKSpan = .thisEvent) {
        do {
            try ek.remove(event, span: span, commit: true)
            reload()
        } catch {
            NSSound.beep()
        }
    }

    func duplicate(_ occurrence: Occurrence) -> EKEvent? {
        guard let source = event(for: occurrence) else { return nil }
        let copy = newEvent()
        copy.title = source.title
        copy.startDate = source.startDate
        copy.endDate = source.endDate
        copy.isAllDay = source.isAllDay
        copy.location = source.location
        copy.notes = source.notes
        copy.url = source.url
        copy.calendar = source.calendar.allowsContentModifications ? source.calendar : defaultCalendar
        for alarm in source.alarms ?? [] {
            copy.addAlarm(EKAlarm(relativeOffset: alarm.relativeOffset))
        }
        guard save(copy) else { return nil }
        EventHistory.shared.added(copy, message: L.historyDuplicated)
        return copy
    }

    func move(_ occurrence: Occurrence, to start: Date, end: Date) {
        guard let event = event(for: occurrence) else { return }
        let before = EventSnapshot(event)
        event.startDate = start
        event.endDate = end
        if save(event, span: .thisEvent) {
            EventHistory.shared.changed(event, from: before, message: L.historyMoved)
        }
    }

    func add(_ entry: ParsedEntry) -> Bool {
        switch entry.kind {
        case .reminder:
            guard remindersGranted else { return false }
            let reminder = EKReminder(eventStore: ek)
            reminder.title = entry.title
            reminder.calendar = entry.reminderList ?? defaultReminderList
            if let start = entry.start {
                var components: Set<Calendar.Component> = [.year, .month, .day]
                if entry.hasTime { components.formUnion([.hour, .minute]) }
                reminder.dueDateComponents = Calendar.current.dateComponents(components, from: start)
                if entry.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: start)) }
            }
            do {
                try ek.save(reminder, commit: true)
                reload()
                EventHistory.shared.reminderAdded(reminder)
                return true
            } catch {
                return false
            }
        case .event:
            let event = newEvent()
            entry.apply(to: event)
            if let calendar = entry.calendar { event.calendar = calendar }
            guard save(event) else { return false }
            EventHistory.shared.added(event)
            return true
        }
    }

    func search(_ query: String) -> Array<Occurrence> {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var seen: Set<String> = []
        var result: Array<Occurrence> = []
        for list in days.values {
            for occurrence in list where !seen.contains(occurrence.id) && occurrence.searchText.contains(needle) {
                seen.insert(occurrence.id)
                result.append(occurrence)
            }
        }
        let now = Date()
        return result.sorted { a, b in
            let aFuture = a.end >= now
            let bFuture = b.end >= now
            if aFuture != bFuture { return aFuture }
            return aFuture ? a.start < b.start : a.start > b.start
        }
    }

    func nextOccurrences(after date: Date, limit: Int) -> Array<Occurrence> {
        var result: Array<Occurrence> = []
        var seen: Set<String> = []
        var day = date.startOfDay
        let horizon = date.adding(days: 30)
        while day < horizon, result.count < limit {
            for occurrence in occurrences(on: day) where !occurrence.isAllDay && occurrence.start > date && !seen.contains(occurrence.id) {
                seen.insert(occurrence.id)
                result.append(occurrence)
            }
            day = day.adding(days: 1)
        }
        return Array(result.prefix(limit))
    }

    func openInCalendar(_ occurrence: Occurrence?) {
        if let occurrence, let external = occurrence.externalIdentifier,
            let encoded = external.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
        {
            NSWorkspace.shared.open(url)
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
