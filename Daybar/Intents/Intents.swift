import AppIntents
import EventKit
import Foundation

nonisolated enum DaybarIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noAccess
    case empty
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccess:
            "Daybar can’t read your calendars. Turn on calendar access in System Settings > Privacy & Security > Calendars."
        case .empty: "Add a title, like “Lunch with Sam tomorrow at noon”."
        case .saveFailed: "Daybar couldn’t save that. Check that the calendar accepts new events."
        }
    }
}

nonisolated struct CalendarEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static let defaultQuery = CalendarQuery()

    let id: String
    let title: String
    let source: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(source)")
    }

    init(id: String, title: String, source: String) {
        self.id = id
        self.title = title
        self.source = source
    }
}

nonisolated struct CalendarQuery: EntityQuery {
    func entities(for identifiers: Array<String>) async -> Array<CalendarEntity> {
        await IntentSupport.calendars().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> Array<CalendarEntity> {
        await IntentSupport.calendars()
    }
}

struct EventEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Event"
    static let defaultQuery = EventQuery()

    let id: String
    let when: String
    @Property(title: "Title") var title: String
    @Property(title: "Start") var start: Date
    @Property(title: "End") var end: Date
    @Property(title: "All-day") var isAllDay: Bool
    @Property(title: "Location") var location: String?
    @Property(title: "Calendar") var calendar: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(when)")
    }

    init(id: String, when: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String?, calendar: String) {
        self.id = id
        self.when = when
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendar = calendar
    }
}

nonisolated struct EventQuery: EntityQuery {
    func entities(for identifiers: Array<String>) async -> Array<EventEntity> {
        await IntentSupport.events(identifiers)
    }

    func suggestedEntities() async throws -> Array<EventEntity> {
        try await IntentSupport.upcoming(limit: 10, calendarIDs: nil)
    }
}

struct AddEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Event"
    static let description: IntentDescription? = IntentDescription("Adds an event to one of your calendars.")

    @Parameter(title: "Title") var eventTitle: String
    @Parameter(title: "Start") var start: Date
    @Parameter(title: "End") var end: Date?
    @Parameter(title: "All-day", default: false) var isAllDay: Bool
    @Parameter(title: "Location") var location: String?
    @Parameter(title: "Calendar") var calendar: CalendarEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$eventTitle) on \(\.$start)") {
            \.$end
            \.$isAllDay
            \.$location
            \.$calendar
        }
    }

    @MainActor
    func perform() throws -> some IntentResult & ReturnsValue<EventEntity> & ProvidesDialog {
        let store = try IntentSupport.store()
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw DaybarIntentError.empty }
        let event = store.newEvent()
        event.title = title
        event.isAllDay = isAllDay
        if isAllDay {
            event.startDate = start.startOfDay
            event.endDate = max(end ?? start, start).startOfDay.adding(days: 1).addingTimeInterval(-1)
        } else {
            event.startDate = start
            event.endDate = max(end ?? start.addingTimeInterval(3_600), start)
        }
        event.location = location
        if let calendar, let found = store.calendar(withIdentifier: calendar.id), found.allowsContentModifications {
            event.calendar = found
        }
        guard store.save(event) else { throw DaybarIntentError.saveFailed }
        EventHistory.shared.added(event)
        let name = event.calendar?.title ?? ""
        return .result(value: IntentSupport.entity(Occurrence(event)), dialog: "Added “\(title)” to \(name).")
    }
}

struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add"
    static let description: IntentDescription? = IntentDescription(
        "Adds an event or reminder from a sentence like “Lunch with Sam tomorrow at noon”.")

    @Parameter(title: "Text") var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Quick add \(\.$text)")
    }

    @MainActor
    func perform() throws -> some IntentResult & ProvidesDialog {
        let store = try IntentSupport.store()
        let entry = EntryParser.parse(text, calendars: store.eventCalendars, reminderLists: store.reminderCalendars)
        guard !entry.isEmpty else { throw DaybarIntentError.empty }
        guard store.add(entry) else { throw DaybarIntentError.saveFailed }
        if entry.kind == .reminder {
            return .result(dialog: "Added the reminder “\(entry.title)”.")
        }
        let name = (entry.calendar ?? store.defaultCalendar)?.title ?? ""
        return .result(dialog: "Added “\(entry.title)” to \(name).")
    }
}

struct UpcomingEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Upcoming Events"
    static let description: IntentDescription? = IntentDescription("Returns your next events in order, starting now.")

    @Parameter(title: "Limit", default: 5, inclusiveRange: (1, 50)) var limit: Int
    @Parameter(title: "Calendars") var calendars: Array<CalendarEntity>?

    static var parameterSummary: some ParameterSummary {
        Summary("Get the next \(\.$limit) events") {
            \.$calendars
        }
    }

    @MainActor
    func perform() throws -> some IntentResult & ReturnsValue<Array<EventEntity>> & ProvidesDialog {
        let ids = calendars.map { Set($0.map(\.id)) }
        let events = try IntentSupport.upcoming(limit: limit, calendarIDs: ids)
        guard !events.isEmpty else {
            return .result(value: events, dialog: "Nothing else is on your calendar.")
        }
        let lines = events.map { "\($0.when): \($0.title)" }.joined(separator: "\n")
        return .result(value: events, dialog: IntentDialog(stringLiteral: lines))
    }
}

struct CalendarFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Show Calendars"
    static let description: IntentDescription? = IntentDescription("Choose which calendars Daybar shows while this Focus is on.")

    @Parameter(title: "Calendars") var calendars: Array<CalendarEntity>?

    var displayRepresentation: DisplayRepresentation {
        guard let calendars, !calendars.isEmpty else { return "All calendars" }
        let names = calendars.map(\.title).formatted(.list(type: .and))
        return DisplayRepresentation(title: "Show \(names)")
    }

    @MainActor
    func perform() -> some IntentResult {
        IntentSupport.applyFocus(calendars)
        return .result()
    }
}

nonisolated struct DaybarShortcuts: AppShortcutsProvider {
    static var appShortcuts: Array<AppShortcut> {
        AppShortcut(
            intent: QuickAddIntent(),
            phrases: ["Add to \(.applicationName)", "Quick add in \(.applicationName)"],
            shortTitle: "Quick Add",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: AddEventIntent(),
            phrases: ["Create an event in \(.applicationName)"],
            shortTitle: "Add Event",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: UpcomingEventsIntent(),
            phrases: ["What’s next in \(.applicationName)", "Show upcoming events in \(.applicationName)"],
            shortTitle: "Upcoming Events",
            systemImageName: "calendar"
        )
    }
}

enum IntentSupport {
    static func store() throws -> CalendarStore {
        let store = CalendarStore.shared
        guard store.access == .granted else { throw DaybarIntentError.noAccess }
        return store
    }

    static func calendars() -> Array<CalendarEntity> {
        CalendarStore.shared.eventCalendars.map {
            CalendarEntity(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "")
        }
    }

    static func entity(_ occurrence: Occurrence) -> EventEntity {
        let day = Fmt.compactDay(occurrence.start)
        return EventEntity(
            id: occurrence.id,
            when: occurrence.isAllDay ? day : "\(day), \(Fmt.time(occurrence.start))",
            title: occurrence.title,
            start: occurrence.start,
            end: occurrence.end,
            isAllDay: occurrence.isAllDay,
            location: occurrence.location,
            calendar: occurrence.calendarTitle
        )
    }

    static func events(_ identifiers: Array<String>) -> Array<EventEntity> {
        identifiers.compactMap { id in
            guard let bar = id.lastIndex(of: "|"), let seconds = Double(id[id.index(after: bar)...]),
                let event = CalendarStore.shared.event(
                    identifier: String(id[..<bar]), start: Date(timeIntervalSinceReferenceDate: seconds))
            else { return nil }
            return entity(Occurrence(event))
        }
    }

    static func upcoming(limit: Int, calendarIDs: Set<String>?) throws -> Array<EventEntity> {
        let store = try store()
        let now = Date.now
        let calendars = store.eventCalendars.filter { calendarIDs?.contains($0.calendarIdentifier) ?? true }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.ek.predicateForEvents(withStart: now, end: now.adding(days: 30), calendars: calendars)
        return store.ek.events(matching: predicate)
            .map(Occurrence.init)
            .filter { $0.end > now && !$0.isDeclined }
            .sorted(by: Occurrence.order)
            .prefix(limit)
            .map(entity)
    }

    static func applyFocus(_ calendars: Array<CalendarEntity>?) {
        let ids = calendars.flatMap { $0.isEmpty ? nil : Set($0.map(\.id)) }
        guard Preferences.shared.focusCalendarIDs != ids else { return }
        Preferences.shared.focusCalendarIDs = ids
        CalendarStore.shared.reload()
    }

    static func start() {
        DaybarShortcuts.updateAppShortcutParameters()
        Task {
            let filter = try? await CalendarFocusFilter.current
            applyFocus(filter?.calendars)
        }
    }
}
