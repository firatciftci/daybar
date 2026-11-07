import EventKit
import SwiftUI

struct QuickAddBar: View {
    let glass: Namespace.ID
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @FocusState private var focused: Bool
    @State private var confirmation: String?

    private var parsed: ParsedEntry {
        EntryParser.parse(model.quickAddText, calendars: store.eventCalendars, reminderLists: store.reminderCalendars, now: model.now)
    }

    var body: some View {
        @Bindable var model = model
        let entry = parsed
        Group {
            HStack(spacing: 8) {
                Button {
                    NSApp.currentEvent?.window?.makeKey()
                    focused = true
                } label: {
                    Image(systemName: entry.kind == .reminder ? "checklist" : "calendar.badge.plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(focused ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 16)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(L.quickAddHelp)
                .accessibilityLabel(L.quickAddIconHelp)
                TextField(L.quickAddPlaceholder, text: $model.quickAddText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .background {
                        TokenHighlighter(
                            text: model.quickAddText,
                            spans: entry.spans,
                            calendarColor: (entry.calendar ?? entry.reminderList).flatMap { NSColor(cgColor: $0.cgColor) },
                            active: focused
                        )
                    }
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if isFocused, model.quickAddText.isEmpty, !isUserInitiated { focused = false }
                    }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else if !model.quickAddText.isEmpty {
                    Text(L.quickAddHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .inputCapsule(in: glass)

            if !entry.isEmpty, focused || !model.quickAddText.isEmpty {
                ParsePreview(entry: entry, store: store)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .glassEffectID("preview", in: glass)
            }
        }
        .animation(.smooth(duration: 0.25), value: entry.isEmpty)
        .animation(Motion.fade, value: confirmation)
    }

    private var isUserInitiated: Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .keyDown:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.window != nil && event.window === NSApp.keyWindow
        default:
            return false
        }
    }

    private func commit() {
        let entry = parsed
        guard !entry.isEmpty else { return }
        if store.add(entry) {
            confirmation = entry.kind == .reminder ? L.reminderSaved : L.eventSaved
            if let start = entry.start, entry.kind == .event {
                model.select(start, scroll: true, animated: true)
            }
            model.quickAddText = ""
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                confirmation = nil
            }
        } else {
            NSSound.beep()
        }
    }
}

private struct TokenHighlighter: NSViewRepresentable {
    let text: String
    let spans: Array<ParsedSpan>
    let calendarColor: NSColor?
    let active: Bool

    func makeNSView(context _: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context _: Context) {
        guard active else { return }
        let text = text
        let colored = spans.map { ($0.range, color(for: $0.role)) }
        DispatchQueue.main.async {
            guard let editor = view.window?.firstResponder as? NSTextView, editor.isFieldEditor, editor.string == text,
                !editor.hasMarkedText()
            else { return }
            Self.paint(editor, colored)
        }
    }

    private func color(for role: ParsedSpan.Role) -> NSColor {
        switch role {
        case .kind: .systemGreen
        case .calendar: calendarColor ?? .controlAccentColor
        case .when: .controlAccentColor
        case .place: .systemOrange
        case .repeats: .systemPurple
        case .alert: .systemPink
        }
    }

    private static func paint(_ editor: NSTextView, _ colored: Array<(NSRange, NSColor)>) {
        let length = editor.string.utf16.count
        if let layout = editor.textLayoutManager, let content = layout.textContentManager {
            let document = content.documentRange
            layout.removeRenderingAttribute(.foregroundColor, for: document)
            for (range, color) in colored where NSMaxRange(range) <= length {
                guard let start = content.location(document.location, offsetBy: range.location),
                    let end = content.location(start, offsetBy: range.length),
                    let span = NSTextRange(location: start, end: end)
                else { continue }
                layout.addRenderingAttribute(.foregroundColor, value: color, for: span)
            }
        } else if let layout = editor.layoutManager {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for (range, color) in colored where NSMaxRange(range) <= length {
                layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
            }
        }
    }
}

private struct ParsePreview: View {
    let entry: ParsedEntry
    let store: CalendarStore

    private var calendar: EKCalendar? {
        entry.kind == .reminder ? (entry.reminderList ?? store.defaultReminderList) : (entry.calendar ?? store.defaultCalendar)
    }

    private var when: String? {
        guard let start = entry.start else { return nil }
        let day = Fmt.compactDay(start)
        if entry.isAllDay || !entry.hasTime {
            return day
        }
        if let end = entry.end, entry.kind == .event {
            return "\(day), \(Fmt.timeRange(start, end))"
        }
        return "\(day), \(Fmt.time(start))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(calendar.map { Color(cgColor: $0.cgColor) } ?? .gray)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                VStack(alignment: .leading, spacing: 3) {
                    if let when {
                        detail(entry.isAllDay ? "sun.max" : "clock", when)
                    }
                    if let location = entry.location {
                        detail("mappin.and.ellipse", location)
                    }
                    if let recurrence = entry.recurrence {
                        detail("repeat", recurrenceTitle(recurrence))
                    }
                    if let minutes = entry.alertMinutes {
                        detail("bell", AlertOffset.title(minutes, allDay: entry.isAllDay))
                    }
                    if let calendar {
                        detail(
                            entry.kind == .reminder ? "checklist" : "calendar",
                            entry.kind == .reminder ? L.quickAddReminderIn(calendar.title) : L.quickAddEventIn(calendar.title)
                        )
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 14)
        }
    }

    private func recurrenceTitle(_ frequency: EKRecurrenceFrequency) -> String {
        switch frequency {
        case .daily: L.repeatDaily
        case .weekly: L.repeatWeekly
        case .monthly: L.repeatMonthly
        case .yearly: L.repeatYearly
        @unknown default: L.repeatCustom
        }
    }
}
