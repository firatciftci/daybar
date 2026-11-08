import EventKit
import SwiftUI

enum SettingsDestination {
    case lastPage
    case calendarSets
    case newCalendarSet
}

@Observable
final class SettingsRoute {
    static let shared = SettingsRoute()

    var wantsNewSet = false

    private init() {}
}

struct CalendarsPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(SettingsRoute.self) private var route
    @State private var editing: CalendarSet?
    @State private var pendingDeletion: CalendarSet?
    @State private var dropTarget: UUID?

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Picker(
                    L.defaultCalendar,
                    selection: Binding(
                        get: { prefs.defaultCalendarID ?? store.defaultCalendar?.calendarIdentifier ?? "" },
                        set: { prefs.defaultCalendarID = $0 }
                    )
                ) {
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                Toggle(L.showDeclined, isOn: $prefs.showDeclined)
                    .onChange(of: prefs.showDeclined) { store.reload() }
                Toggle(L.showReminders, isOn: $prefs.showReminders)
                    .onChange(of: prefs.showReminders) { store.reload() }
            }
            Section {
                if prefs.calendarSets.isEmpty {
                    EmptySetsRow()
                } else {
                    ForEach(prefs.calendarSets) { set in
                        CalendarSetRow(set: set, active: prefs.activeSetID == set.id, calendars: members(of: set)) {
                            editing = set
                        }
                        .contextMenu { menu(for: set) }
                        .draggable(set.id.uuidString) {
                            SetTile(symbol: set.symbol, size: 28)
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            drop(ids.first, onto: set)
                        } isTargeted: { targeted in
                            dropTarget = targeted ? set.id : (dropTarget == set.id ? nil : dropTarget)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.tint.opacity(dropTarget == set.id ? 0.14 : 0))
                                .padding(-5)
                                .animation(Motion.fade, value: dropTarget)
                        }
                    }
                }
            } header: {
                Text(L.calendarSets)
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if !prefs.calendarSets.isEmpty {
                        Text(L.calendarSetsFooter)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(L.addSet, action: beginNewSet)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 500, alignment: .top)
        .sheet(item: $editing) { set in
            CalendarSetEditor(set: set, isNew: !prefs.calendarSets.contains { $0.id == set.id }, onSave: save) {
                delete(set)
            }
        }
        .confirmationDialog(
            pendingDeletion.map { L.deleteSetTitle($0.name) } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { set in
            Button(L.deleteSet, role: .destructive) { delete(set) }
            Button(L.cancel, role: .cancel) {}
        } message: { set in
            Text(prefs.activeSetID == set.id ? L.deleteActiveSetMessage : L.deleteSetMessage)
        }
        .onChange(of: route.wantsNewSet, initial: true) {
            guard route.wantsNewSet else { return }
            route.wantsNewSet = false
            beginNewSet()
        }
    }

    @ViewBuilder
    private func menu(for set: CalendarSet) -> some View {
        let index = prefs.calendarSets.firstIndex { $0.id == set.id } ?? 0
        Button(L.showInPanel) { show(set) }
            .disabled(prefs.activeSetID == set.id)
        Button(L.editEllipsis) { editing = set }
        Button(L.duplicate) { duplicate(set) }
        Divider()
        Button(L.moveUp) { move(from: index, to: index - 1) }
            .disabled(index == 0)
        Button(L.moveDown) { move(from: index, to: index + 1) }
            .disabled(index == prefs.calendarSets.count - 1)
        Divider()
        Button(L.deleteSetEllipsis, role: .destructive) { pendingDeletion = set }
    }

    private func members(of set: CalendarSet) -> Array<EKCalendar> {
        store.eventCalendars.filter { set.calendarIDs.contains($0.calendarIdentifier) }
    }

    private func beginNewSet() {
        let visible = Set(store.visibleCalendars.map(\.calendarIdentifier))
        editing = CalendarSet(name: "", calendarIDs: visible)
    }

    private func save(_ set: CalendarSet) {
        withAnimation(Motion.content) { prefs.saveSet(set) }
        if prefs.activeSetID == set.id { store.reload() }
    }

    private func delete(_ set: CalendarSet) {
        let wasActive = prefs.activeSetID == set.id
        withAnimation(Motion.content) { prefs.deleteSet(set.id) }
        if wasActive { store.reload() }
    }

    private func show(_ set: CalendarSet) {
        prefs.activeSetID = set.id
        store.reload()
    }

    private func duplicate(_ set: CalendarSet) {
        let names = Set(prefs.calendarSets.map { $0.name.lowercased() })
        var name = L.setCopyName(set.name)
        var number = 2
        while names.contains(name.lowercased()) {
            name = "\(L.setCopyName(set.name)) \(number)"
            number += 1
        }
        let copy = CalendarSet(name: name, symbol: set.symbol, calendarIDs: set.calendarIDs)
        let index = (prefs.calendarSets.firstIndex { $0.id == set.id } ?? prefs.calendarSets.count - 1) + 1
        withAnimation(Motion.content) { prefs.calendarSets.insert(copy, at: index) }
    }

    private func drop(_ id: String?, onto target: CalendarSet) -> Bool {
        dropTarget = nil
        guard let id = id.flatMap(UUID.init(uuidString:)), id != target.id,
            let source = prefs.calendarSets.firstIndex(where: { $0.id == id }),
            let destination = prefs.calendarSets.firstIndex(where: { $0.id == target.id })
        else { return false }
        withAnimation(Motion.content) {
            prefs.calendarSets.move(fromOffsets: IndexSet(integer: source), toOffset: source < destination ? destination + 1 : destination)
        }
        return true
    }

    private func move(from source: Int, to destination: Int) {
        withAnimation(Motion.content) { prefs.calendarSets.swapAt(source, destination) }
    }
}

struct SetTile: View {
    let symbol: String
    var size: CGFloat = 26
    var muted = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(muted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor.gradient))
            }
            .accessibilityHidden(true)
    }
}

private struct EmptySetsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SetTile(symbol: CalendarSet.symbols[0], size: 34, muted: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.noSetsTitle)
                Text(L.noSetsDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CalendarSetRow: View {
    let set: CalendarSet
    let active: Bool
    let calendars: Array<EKCalendar>
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SetTile(symbol: set.symbol, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(set.name)
                        .lineLimit(1)
                    if active {
                        Text(L.showingBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(.tint.opacity(0.14), in: .capsule)
                    }
                }
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(calendars.prefix(6), id: \.calendarIdentifier) { calendar in
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text(L.calendarCount(calendars.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(L.editEllipsis, action: edit)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: edit)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: L.editEllipsis, edit)
    }
}

private struct CalendarSetEditor: View {
    let isNew: Bool
    let onSave: (CalendarSet) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs
    @State private var draft: CalendarSet
    @State private var symbolChosen: Bool
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    init(set: CalendarSet, isNew: Bool, onSave: @escaping (CalendarSet) -> Void, onDelete: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: set)
        _symbolChosen = State(initialValue: !isNew)
    }

    private var name: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameTaken: Bool {
        prefs.calendarSets.contains { $0.id != draft.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private var hasCalendars: Bool {
        store.eventCalendars.contains { draft.calendarIDs.contains($0.calendarIdentifier) }
    }

    private var problem: String? {
        if nameTaken { return L.duplicateSetName }
        if !hasCalendars { return L.chooseCalendar }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section(L.setIcon) {
                    symbolGrid
                }
                ForEach(store.calendarsBySource, id: \.source) { group in
                    calendarSection(group.source, group.calendars)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 8) {
                if !isNew {
                    Button(L.deleteSetEllipsis, role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button(L.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? L.createSet : L.save, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || problem != nil)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 460, height: 480)
        .onAppear { nameFocused = isNew }
        .confirmationDialog(L.deleteSetTitle(draft.name), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L.deleteSet, role: .destructive) {
                onDelete()
                dismiss()
            }
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(prefs.activeSetID == draft.id ? L.deleteActiveSetMessage : L.deleteSetMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SetTile(symbol: draft.symbol, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(isNew ? L.newSet : L.editSetTitle)
                    .font(.headline)
                TextField(L.setName, text: $draft.name, prompt: Text(L.setNamePlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .onChange(of: draft.name) {
                        guard !symbolChosen else { return }
                        let symbol = CalendarSet.suggestedSymbol(for: draft.name) ?? CalendarSet.symbols[0]
                        guard symbol != draft.symbol else { return }
                        withAnimation(Motion.select) { draft.symbol = symbol }
                    }
                Text(problem ?? " ")
                    .font(.caption)
                    .foregroundStyle(nameTaken ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .animation(Motion.fade, value: problem)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 8) {
            ForEach(CalendarSet.symbols, id: \.self) { symbol in
                let selected = draft.symbol == symbol
                Button {
                    symbolChosen = true
                    withAnimation(Motion.select) { draft.symbol = symbol }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.7)))
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func calendarSection(_ source: String, _ calendars: Array<EKCalendar>) -> some View {
        let ids = Set(calendars.map(\.calendarIdentifier))
        let allChosen = ids.isSubset(of: draft.calendarIDs)
        return Section {
            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                Toggle(
                    isOn: Binding(
                        get: { draft.calendarIDs.contains(calendar.calendarIdentifier) },
                        set: { on in
                            if on {
                                draft.calendarIDs.insert(calendar.calendarIdentifier)
                            } else {
                                draft.calendarIDs.remove(calendar.calendarIdentifier)
                            }
                        }
                    )
                ) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: 9, height: 9)
                        Text(calendar.title)
                    }
                }
                .toggleStyle(.checkbox)
            }
        } header: {
            HStack {
                Text(source)
                Spacer()
                Button(allChosen ? L.deselectAll : L.selectAll) {
                    if allChosen {
                        draft.calendarIDs.subtract(ids)
                    } else {
                        draft.calendarIDs.formUnion(ids)
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private func save() {
        guard !name.isEmpty, problem == nil else { return }
        var set = draft
        set.name = name
        onSave(set)
        dismiss()
    }
}
