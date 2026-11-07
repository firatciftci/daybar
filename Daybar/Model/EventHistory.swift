import AppKit
import EventKit
import Observation

struct EventSnapshot {
    let title: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    let calendarID: String?
    let timeZone: TimeZone?
    let availability: EKEventAvailability
    let alarms: Array<EKAlarm>
    let rules: Array<EKRecurrenceRule>

    init(_ event: EKEvent) {
        title = event.title
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        location = event.location
        notes = event.notes
        url = event.url
        calendarID = event.calendar?.calendarIdentifier
        timeZone = event.timeZone
        availability = event.availability
        alarms = (event.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        rules = (event.recurrenceRules ?? []).compactMap { $0.copy() as? EKRecurrenceRule }
    }

    func apply(to event: EKEvent, in store: CalendarStore, includingRules: Bool) {
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = end
        event.timeZone = timeZone
        event.location = location
        event.notes = notes
        event.url = url
        event.availability = availability
        if let calendarID, let calendar = store.ek.calendar(withIdentifier: calendarID), calendar.allowsContentModifications {
            event.calendar = calendar
        } else if event.calendar == nil {
            event.calendar = store.defaultCalendar
        }
        for alarm in event.alarms ?? [] {
            event.removeAlarm(alarm)
        }
        for alarm in alarms {
            if let copy = alarm.copy() as? EKAlarm { event.addAlarm(copy) }
        }
        guard includingRules else { return }
        for rule in event.recurrenceRules ?? [] {
            event.removeRecurrenceRule(rule)
        }
        for rule in rules {
            if let copy = rule.copy() as? EKRecurrenceRule { event.addRecurrenceRule(copy) }
        }
    }
}

@Observable
final class EventHistory {
    static let shared = EventHistory()

    struct Notice: Equatable {
        let id = UUID()
        let message: String
    }

    private struct Step {
        let message: String
        let undo: () -> Void
        let redo: () -> Void
    }

    private final class Handle {
        var identifier: String
        var start: Date

        init(_ event: EKEvent) {
            identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            start = event.startDate
        }

        init(identifier: String, start: Date) {
            self.identifier = identifier
            self.start = start
        }

        func update(_ event: EKEvent) {
            identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            start = event.startDate
        }
    }

    private(set) var notice: Notice?
    @ObservationIgnored var onApply: (() -> Void)?
    @ObservationIgnored private var undoStack: Array<Step> = []
    @ObservationIgnored private var redoStack: Array<Step> = []
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    private var store: CalendarStore { .shared }

    private init() {}

    func undo() {
        guard let step = undoStack.popLast() else {
            NSSound.beep()
            return
        }
        step.undo()
        redoStack.append(step)
        dismissNotice()
        onApply?()
    }

    func redo() {
        guard let step = redoStack.popLast() else {
            NSSound.beep()
            return
        }
        step.redo()
        undoStack.append(step)
        show(step.message)
        onApply?()
    }

    func dismissNotice() {
        dismissal?.cancel()
        notice = nil
    }

    func added(_ event: EKEvent, message: String = L.historyAdded) {
        let handle = Handle(event)
        let snapshot = EventSnapshot(event)
        record(message) { [weak self] in
            self?.remove(handle)
        } redo: { [weak self] in
            self?.recreate(snapshot, into: handle, includingRules: true)
        }
    }

    func changed(_ event: EKEvent, from before: EventSnapshot, message: String, rulesChanged: Bool = false) {
        let handle = Handle(event)
        let after = EventSnapshot(event)
        let span: EKSpan = rulesChanged ? .futureEvents : .thisEvent
        record(message) { [weak self] in
            self?.restore(before, into: handle, includingRules: rulesChanged, span: span)
        } redo: { [weak self] in
            self?.restore(after, into: handle, includingRules: rulesChanged, span: span)
        }
    }

    func deleted(_ snapshot: EventSnapshot, keepingRules: Bool) {
        let handle = Handle(identifier: "", start: snapshot.start)
        record(L.historyDeleted) { [weak self] in
            self?.recreate(snapshot, into: handle, includingRules: keepingRules)
        } redo: { [weak self] in
            self?.remove(handle)
        }
    }

    func reminderAdded(_ reminder: EKReminder) {
        var identifier = reminder.calendarItemIdentifier
        let title = reminder.title
        let calendar = reminder.calendar
        let due = reminder.dueDateComponents
        let alarms = (reminder.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        record(L.historyReminderAdded) { [weak self] in
            guard let self, let item = store.ek.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
            try? store.ek.remove(item, commit: true)
            store.reload()
        } redo: { [weak self] in
            guard let self else { return }
            let item = EKReminder(eventStore: store.ek)
            item.title = title
            item.calendar = calendar ?? store.defaultReminderList
            item.dueDateComponents = due
            for alarm in alarms {
                if let copy = alarm.copy() as? EKAlarm { item.addAlarm(copy) }
            }
            try? store.ek.save(item, commit: true)
            identifier = item.calendarItemIdentifier
            store.reload()
        }
    }

    func reminderCompleted(_ identifier: String) {
        record(L.historyCompleted) { [weak self] in
            self?.setCompleted(identifier, false)
        } redo: { [weak self] in
            self?.setCompleted(identifier, true)
        }
    }

    private func record(_ message: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(Step(message: message, undo: undo, redo: redo))
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
        show(message)
    }

    private func show(_ message: String) {
        dismissal?.cancel()
        let next = Notice(message: message)
        notice = next
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, self?.notice == next else { return }
            self?.notice = nil
        }
    }

    private func remove(_ handle: Handle) {
        guard let event = store.event(identifier: handle.identifier, start: handle.start) else { return }
        store.delete(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent)
    }

    private func recreate(_ snapshot: EventSnapshot, into handle: Handle, includingRules: Bool) {
        let event = store.newEvent()
        snapshot.apply(to: event, in: store, includingRules: includingRules)
        if store.save(event) { handle.update(event) }
    }

    private func restore(_ snapshot: EventSnapshot, into handle: Handle, includingRules: Bool, span: EKSpan) {
        guard let event = store.event(identifier: handle.identifier, start: handle.start) else { return }
        snapshot.apply(to: event, in: store, includingRules: includingRules)
        if store.save(event, span: span) { handle.update(event) }
    }

    private func setCompleted(_ identifier: String, _ completed: Bool) {
        guard let reminder = store.ek.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.ek.save(reminder, commit: true)
        store.reload()
    }
}
