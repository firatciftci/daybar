import EventKit
import SwiftUI

struct EventTitleField: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @FocusState private var focus: EditorField?

    var body: some View {
        @Bindable var model = model
        let tint =
            store.writableCalendars.first { $0.calendarIdentifier == model.draft.calendarID }.map { Color(nsColor: $0.color) }
            ?? .accentColor
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .frame(width: 16)
                .animation(Motion.fade, value: model.draft.calendarID)
            TextField(L.titleField, text: $model.draft.title, prompt: Text(L.newEventTitle))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($focus, equals: .title)
                .onSubmit { model.requestSave() }
        }
        .modifier(EditorFocusSync(focus: $focus, owned: [.title]))
    }
}

struct EventEditingBar: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        ZStack {
            Text(model.draft.isNew ? L.newEvent : L.editEvent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 150)
            HStack(spacing: 8) {
                Button(L.cancel) {
                    model.requestCancelEditing()
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Spacer(minLength: 0)
                Button {
                    model.requestSave()
                } label: {
                    Text(L.save)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSave)
            }
        }
    }
}

struct EventForm: View {
    @Environment(PanelModel.self) private var model
    @Environment(CalendarStore.self) private var store
    @FocusState private var focus: EditorField?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField(L.locationField, text: $model.draft.location, prompt: Text(L.locationField))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($focus, equals: .location)
            }
            Section {
                Toggle(L.allDay, isOn: $model.draft.isAllDay.animation(.snappy))
                    .focused($focus, equals: .allDay)
                DatePicker(
                    L.starts, selection: Binding(get: { model.draft.start }, set: { model.moveDraftStart(to: $0) }),
                    displayedComponents: components
                )
                .focused($focus, equals: .start)
                DatePicker(L.ends, selection: $model.draft.end, in: model.draft.start..., displayedComponents: components)
                    .focused($focus, equals: .end)
            }
            Section {
                Picker(
                    L.repeatField,
                    selection: Binding {
                        model.draft.recurrence
                    } set: {
                        model.draft.choose($0)
                    }.animation(.snappy)
                ) {
                    ForEach(RecurrenceChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .focused($focus, equals: .recurrence)
                if model.draft.recurrence == .custom {
                    RepeatRows(rule: $model.draft.repeatRule, start: model.draft.start)
                }
            }
            Section {
                AlertRows(alerts: $model.draft.alerts, allDay: model.draft.isAllDay, focus: $focus)
                Picker(L.calendarField, selection: $model.draft.calendarID) {
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Image(nsImage: NSImage.swatch(calendar.color))
                        }
                        .tag(calendar.calendarIdentifier)
                    }
                }
                .focused($focus, equals: .calendar)
            }
            Section {
                TextField(L.urlField, text: $model.draft.url, prompt: Text(L.urlField))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .url)
                TextField(L.notesField, text: $model.draft.notes, prompt: Text(L.notesField), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...)
                    .focused($focus, equals: .notes)
            }
            .labelsHidden()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.top, 2, for: .scrollContent)
        .modifier(EditorFocusSync(focus: $focus, owned: [.location, .allDay, .start, .end, .recurrence, .alert, .calendar, .url, .notes]))
    }

    private var components: DatePickerComponents {
        model.draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }
}

private struct EditorFocusSync: ViewModifier {
    let focus: FocusState<EditorField?>.Binding
    let owned: Set<EditorField>
    @Environment(PanelModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onChange(of: focus.wrappedValue) { _, field in
                if let field { model.editorFocus = field }
            }
            .onChange(of: model.editorFocus) { _, field in
                if let field, owned.contains(field), focus.wrappedValue != field { focus.wrappedValue = field }
            }
            .task(id: model.draft.id) {
                try? await Task.sleep(for: .milliseconds(30))
                if let field = model.editorFocus, owned.contains(field) { focus.wrappedValue = field }
            }
    }
}
