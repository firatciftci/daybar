import EventKit
import SwiftUI

struct CalendarSetsMenu: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Preferences.self) private var prefs
    @Environment(PanelModel.self) private var model

    private var focused: Bool { prefs.focusCalendarIDs != nil }

    var body: some View {
        Menu {
            if focused {
                Section {
                    Text(L.focusChoosing)
                }
            }
            if prefs.calendarSets.isEmpty {
                calendarSections
                    .disabled(focused)
                Divider()
                Button(L.newSetEllipsis, systemImage: "plus") { model.onOpenSettings?(.newCalendarSet) }
            } else {
                Picker(
                    L.setsMenuHeader,
                    selection: Binding(
                        get: { prefs.activeSetID },
                        set: { id in
                            prefs.activeSetID = id
                            store.reload()
                        })
                ) {
                    Label(L.allCalendars, systemImage: "square.3.layers.3d").tag(UUID?.none)
                    ForEach(prefs.calendarSets) { set in
                        Label(set.name, systemImage: set.symbol).tag(UUID?.some(set.id))
                    }
                }
                .pickerStyle(.inline)
                .disabled(focused)
                Menu(prefs.activeSet.map { L.calendarsInSet($0.name) } ?? L.calendars) {
                    calendarSections
                }
                .disabled(focused)
                Divider()
                Button(L.editSets, systemImage: "slider.horizontal.3") { model.onOpenSettings?(.calendarSets) }
            }
        } label: {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel(L.calendars)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(GlassCircleStyle(active: prefs.activeSet != nil))
        .fixedSize()
        .help(prefs.activeSet.map { L.showingSetHelp($0.name) } ?? L.calendars)
    }

    private var symbol: String {
        if let set = prefs.activeSet { return set.symbol }
        return prefs.hiddenCalendarIDs.isEmpty ? "square.3.layers.3d" : "square.3.layers.3d.top.filled"
    }

    private var calendarSections: some View {
        let lastInSet: String? = prefs.activeSet.flatMap { set in
            let members = store.eventCalendars.filter { set.calendarIDs.contains($0.calendarIdentifier) }
            return members.count == 1 ? members.first?.calendarIdentifier : nil
        }
        return ForEach(store.calendarsBySource, id: \.source) { group in
            Section(group.source) {
                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(
                        isOn: Binding(
                            get: { prefs.isCalendarVisible(calendar.calendarIdentifier) },
                            set: { _ in
                                prefs.toggleCalendar(calendar.calendarIdentifier)
                                store.reload()
                            }
                        )
                    ) {
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Image(nsImage: .swatch(NSColor(cgColor: calendar.cgColor) ?? .gray))
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(calendar.calendarIdentifier == lastInSet)
                }
            }
        }
    }
}
