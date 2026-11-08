import EventKit
import Observation
import SwiftUI

enum PanelRoute: Equatable {
    case home
    case detail(Occurrence)
}

enum InputMode: Equatable {
    case quickAdd
    case search
    case event
}

enum ResizePhase {
    case began
    case changed
    case ended
    case reset
}

enum EditorField: Hashable {
    case title
    case location
    case allDay
    case start
    case end
    case recurrence
    case alert
    case calendar
    case url
    case notes
}

enum DayMark: Equatable {
    case plain
    case ring
    case dim
}

struct ScrollRequest: Equatable, Identifiable {
    let id = UUID()
    let day: Date
    let animated: Bool
}

@Observable
final class PanelModel {
    var mode: PanelMode = Preferences.shared.defaultView
    var route: PanelRoute = .home
    var input: InputMode = .quickAdd
    var draft = EventDraft.new(start: .now, end: .now, allDay: false)
    var forward = true
    var selectionFollowsScroll = false
    var askSaveSpan = false
    var askDiscard = false
    var draftBaseline = EventDraft.new(start: .now, end: .now, allDay: false)
    var editorFocus: EditorField?
    var selectedDate = Date().startOfDay
    var displayedMonth = Date().startOfMonth
    var deleteRequest: Occurrence?
    var isDetached = false
    var scrollRequest: ScrollRequest?
    var quickAddText = ""
    var searchQuery = ""
    var gridDirection = 1
    var openCount = 0
    var now = Date()

    @ObservationIgnored var onDismiss: (() -> Void)?
    @ObservationIgnored var onOpenSettings: ((SettingsDestination) -> Void)?
    @ObservationIgnored var onResize: ((ResizePhase) -> Void)?

    func prepareForOpen() {
        now = .now
        openCount += 1
        if input == .event { return }
        route = .home
        input = .quickAdd
        searchQuery = ""
        if !isDetached {
            mode = Preferences.shared.defaultView
            select(Date(), scroll: true, animated: false)
        }
    }

    func select(_ date: Date, scroll: Bool = true, animated: Bool = true) {
        let day = date.startOfDay
        if selectionFollowsScroll {
            Task { self.setSelectionFollowsScroll(false) }
        }
        gridDirection = day >= selectedDate ? 1 : -1
        selectedDate = day
        if !day.isSameMonth(as: displayedMonth) {
            displayedMonth = day.startOfMonth
        }
        CalendarStore.shared.ensureLoaded(around: day)
        if scroll {
            scrollRequest = ScrollRequest(day: day, animated: animated)
        }
    }

    func syncFromList(_ day: Date) {
        guard !day.isSameDay(as: selectedDate) else { return }
        guard selectionFollowsScroll else {
            setSelectionFollowsScroll(true)
            Task { self.syncFromList(day) }
            return
        }
        withAnimation(Motion.content) {
            gridDirection = day > selectedDate ? 1 : -1
            selectedDate = day
            if !day.isSameMonth(as: displayedMonth) {
                displayedMonth = day.startOfMonth
            }
        }
        CalendarStore.shared.ensureLoaded(around: day)
    }

    private func setSelectionFollowsScroll(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectionFollowsScroll = value
        }
    }

    func goToToday() {
        select(Date(), scroll: true, animated: false)
    }

    func shiftMonth(_ delta: Int) {
        showMonth(displayedMonth.adding(months: delta))
    }

    func showMonth(_ month: Date) {
        let month = month.startOfMonth
        gridDirection = month >= displayedMonth ? 1 : -1
        displayedMonth = month
        select(Date().isSameMonth(as: month) ? Date() : month, scroll: true, animated: false)
    }

    func shift(days delta: Int) {
        select(selectedDate.adding(days: delta), scroll: true, animated: true)
    }

    func show(_ occurrence: Occurrence) {
        withAnimation(Motion.navigate) {
            forward = true
            route = .detail(occurrence)
        }
    }

    func compose(start: Date? = nil, end: Date? = nil, allDay: Bool = false) {
        let begin = start ?? defaultStart(for: selectedDate)
        beginEditing(EventDraft.new(start: begin, end: end ?? begin.addingTimeInterval(3_600), allDay: allDay))
    }

    func compose(on day: Date) {
        if input == .event {
            pick(day)
            return
        }
        select(day, scroll: true, animated: false)
        compose(start: defaultStart(for: day))
    }

    func edit(_ occurrence: Occurrence) {
        guard let event = CalendarStore.shared.event(for: occurrence) else { return }
        select(occurrence.start, scroll: false)
        beginEditing(EventDraft(event: event, occurrence: occurrence))
    }

    func pick(_ date: Date) {
        select(date)
        guard input == .event else { return }
        let delta = Calendar.current.dateComponents([.day], from: draft.start.startOfDay, to: date.startOfDay).day ?? 0
        guard delta != 0 else { return }
        draft.start = draft.start.adding(days: delta)
        draft.end = draft.end.adding(days: delta)
    }

    func moveDraftStart(to start: Date) {
        draft.end = draft.end.addingTimeInterval(start.timeIntervalSince(draft.start))
        draft.start = start
        select(start, scroll: false)
    }

    var hasUnsavedChanges: Bool {
        draft != draftBaseline
    }

    func requestCancelEditing() {
        if hasUnsavedChanges {
            askDiscard = true
        } else {
            finishEditing(saved: nil)
        }
    }

    func delete(_ occurrence: Occurrence, span: EKSpan) {
        deleteRequest = nil
        guard let event = CalendarStore.shared.event(for: occurrence) else { return }
        let snapshot = EventSnapshot(event)
        let recurring = event.hasRecurrenceRules
        CalendarStore.shared.delete(event, span: span)
        if !recurring || span == .thisEvent {
            EventHistory.shared.deleted(snapshot, keepingRules: !recurring)
        }
        if case .detail(let shown) = route, shown.id == occurrence.id {
            back()
        }
    }

    var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func requestSave() {
        guard canSave else { return }
        if draft.wasRecurring {
            askSaveSpan = true
        } else {
            save(.thisEvent)
        }
    }

    func save(_ span: EKSpan) {
        let store = CalendarStore.shared
        let event: EKEvent? = if let occurrence = draft.occurrence { store.event(for: occurrence) } else { store.newEvent() }
        guard let event else { return }
        let before = draft.isNew ? nil : EventSnapshot(event)
        let wasRecurring = event.hasRecurrenceRules
        draft.apply(to: event, store: store)
        guard store.save(event, span: span) else {
            NSSound.beep()
            return
        }
        if let before {
            if !wasRecurring || span == .thisEvent {
                EventHistory.shared.changed(
                    event, from: before, message: L.historyEdited, rulesChanged: !wasRecurring && event.hasRecurrenceRules)
            }
        } else {
            EventHistory.shared.added(event)
        }
        let saved = Occurrence(event)
        select(saved.start, scroll: true, animated: false)
        finishEditing(saved: saved)
    }

    func mark(for date: Date) -> DayMark {
        switch input {
        case .quickAdd:
            return .plain
        case .search:
            let needle = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return .plain }
            return CalendarStore.shared.occurrences(on: date).contains { $0.searchText.contains(needle) } ? .ring : .dim
        case .event:
            let day = date.startOfDay
            return day >= draft.start.startOfDay && day <= max(draft.end, draft.start).startOfDay ? .ring : .plain
        }
    }

    func toggleSearch() {
        withAnimation(Motion.navigate) {
            if input == .search {
                searchQuery = ""
                input = .quickAdd
            } else {
                forward = false
                route = .home
                input = .search
            }
        }
    }

    func dismissInput() {
        guard input != .quickAdd else { return }
        withAnimation(Motion.navigate) {
            searchQuery = ""
            input = .quickAdd
        }
    }

    func advanceEditorFocus(backward: Bool, fullKeyboardAccess: Bool) {
        let order: Array<EditorField> =
            fullKeyboardAccess
            ? [.title, .location, .allDay, .start, .end, .recurrence, .alert, .calendar, .url, .notes]
            : [.title, .location, .start, .end, .url, .notes]
        if let current = editorFocus, let index = order.firstIndex(of: current) {
            editorFocus = order[(index + (backward ? order.count - 1 : 1)) % order.count]
        } else {
            editorFocus = backward ? order.last : order.first
        }
    }

    func finishEditing(saved: Occurrence?) {
        let target = saved ?? draft.occurrence
        editorFocus = nil
        withAnimation(Motion.navigate) {
            input = .quickAdd
            if let target {
                forward = saved != nil
                route = .detail(target)
            }
        }
    }

    func refreshShownEvent() {
        guard case .detail(let shown) = route else { return }
        guard let event = CalendarStore.shared.event(for: shown) else {
            back()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { route = .detail(Occurrence(event)) }
    }

    func back() {
        switch route {
        case .detail:
            withAnimation(Motion.navigate) {
                forward = false
                route = .home
            }
        case .home:
            switch input {
            case .event:
                requestCancelEditing()
            case .search:
                if searchQuery.isEmpty {
                    dismissInput()
                } else {
                    searchQuery = ""
                }
            case .quickAdd:
                if quickAddText.isEmpty {
                    onDismiss?()
                } else {
                    quickAddText = ""
                }
            }
        }
    }

    private func beginEditing(_ newDraft: EventDraft) {
        withAnimation(Motion.navigate) {
            forward = route != .home
            draft = newDraft
            draftBaseline = newDraft
            editorFocus = newDraft.isNew ? .title : nil
            route = .home
            input = .event
        }
    }

    private func defaultStart(for day: Date) -> Date {
        if day.isToday { return EntryParser.nextSlot() }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
