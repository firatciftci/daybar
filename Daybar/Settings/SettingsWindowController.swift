import AppKit
import EventKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        func add(_ title: String, symbol: String, _ pane: some View) {
            let host = NSHostingController(
                rootView:
                    pane
                    .environment(CalendarStore.shared)
                    .environment(Preferences.shared)
                    .environment(WeatherModel.shared)
                    .environment(Permissions.shared)
                    .frame(width: 500)
                    .fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(L.tabGeneral, symbol: "gearshape", GeneralPane())
        add(L.tabMenuBar, symbol: "menubar.rectangle", MenuBarPane())
        add(L.tabCalendars, symbol: "calendar", CalendarsPane())
        add(L.tabWeather, symbol: "cloud.sun", WeatherPane())
        add(L.tabPermissions, symbol: "hand.raised", PermissionsPane())
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.presentInFront()
    }
}

private struct PermissionsPane: View {
    @Environment(Permissions.self) private var permissions

    var body: some View {
        VStack(spacing: 10) {
            PermissionList()
            Text(L.permissionsFooter)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onAppear { permissions.refresh() }
    }
}

private struct GeneralPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle(L.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                KeyboardShortcuts.Recorder(L.shortcut, name: .togglePanel)
            }
            Section {
                Picker(L.defaultView, selection: $prefs.defaultView) {
                    ForEach(PanelMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Picker(L.weekStart, selection: $prefs.weekStart) {
                    Text(L.systemSetting).tag(0)
                    Divider()
                    ForEach([1, 2, 7], id: \.self) { day in
                        Text(Calendar.current.standaloneWeekdaySymbols[day - 1]).tag(day)
                    }
                }
                .onChange(of: prefs.weekStart) { store.reload() }
                Toggle(L.compactLayout, isOn: $prefs.compact)
                Toggle(L.showQuickAdd, isOn: $prefs.showQuickAdd)
                Picker(L.allDayPlacement, selection: $prefs.separateAllDay) {
                    Text(L.allDayInline).tag(false)
                    Text(L.allDayAbove).tag(true)
                }
                Picker(L.reminderPlacement, selection: $prefs.remindersByTime) {
                    Text(L.remindersGrouped).tag(false)
                    Text(L.remindersMixed).tag(true)
                }
                .disabled(!prefs.showReminders)
                Toggle(L.weekNumbers, isOn: $prefs.showWeekNumbers)
                TimeZonePicker(selection: $prefs.secondTimeZoneID)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TimeZonePicker: View {
    @Binding var selection: String?

    private var regions: Array<(String, Array<String>)> {
        var order: Array<String> = []
        var groups: [String: Array<String>] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers where identifier.contains("/") {
            let region = String(identifier.split(separator: "/").first ?? "")
            if groups[region] == nil { order.append(region) }
            groups[region, default: []].append(identifier)
        }
        return order.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        LabeledContent(L.secondTimeZone) {
            Menu {
                Button(L.noneOption) { selection = nil }
                Divider()
                ForEach(regions, id: \.0) { region, zones in
                    Menu(region.replacingOccurrences(of: "_", with: " ")) {
                        ForEach(zones, id: \.self) { identifier in
                            Button(label(for: identifier)) { selection = identifier }
                        }
                    }
                }
            } label: {
                Text(selection.flatMap(TimeZone.init(identifier:)).map { label(for: $0.identifier) } ?? L.noneOption)
            }
            .fixedSize()
        }
    }

    private func label(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let name = Fmt.zoneName(zone)
        let offset = zone.localizedName(for: .shortGeneric, locale: .current) ?? ""
        return offset.isEmpty ? name : "\(name) (\(offset))"
    }
}

private struct MenuBarPane: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle(L.meetingIcon, isOn: $prefs.showMeetingIcon)
                Picker(L.meetingLead, selection: $prefs.meetingLeadMinutes) {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text(L.minutesBefore(minutes)).tag(minutes)
                    }
                }
                .disabled(!prefs.showMeetingIcon)
            } footer: {
                Text(L.meetingIconFooter)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarsPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @State private var pendingDeletion: CalendarSet?

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
                ForEach($prefs.calendarSets) { $set in
                    DisclosureGroup {
                        ForEach(store.eventCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { set.calendarIDs.contains(calendar.calendarIdentifier) },
                                    set: { on in
                                        if on {
                                            set.calendarIDs.insert(calendar.calendarIdentifier)
                                        } else {
                                            set.calendarIDs.remove(calendar.calendarIdentifier)
                                        }
                                        store.reload()
                                    }
                                )
                            ) {
                                Label {
                                    Text(calendar.title)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(Color(cgColor: calendar.cgColor))
                                }
                            }
                        }
                        Button(L.deleteSet, role: .destructive) {
                            pendingDeletion = set
                        }
                    } label: {
                        TextField(L.calendarSets, text: $set.name, prompt: Text(L.setNamePlaceholder))
                            .textFieldStyle(.plain)
                    }
                }
                Button(L.newSet) {
                    let visible = Set(store.visibleCalendars.map(\.calendarIdentifier))
                    prefs.calendarSets.append(CalendarSet(name: "", calendarIDs: visible))
                }
            } header: {
                Text(L.calendarSets)
            } footer: {
                Text(L.calendarSetsFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            pendingDeletion.map { $0.name.isEmpty ? L.deleteSetUntitledTitle : L.deleteSetTitle($0.name) } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { set in
            Button(L.deleteSet, role: .destructive) {
                if prefs.activeSetID == set.id { prefs.activeSetID = nil }
                prefs.calendarSets.removeAll { $0.id == set.id }
                store.reload()
            }
            Button(L.cancel, role: .cancel) {}
        } message: { _ in
            Text(L.deleteSetMessage)
        }
    }
}

private struct WeatherPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(WeatherModel.self) private var weather
    @State private var city = ""
    @State private var lookupFailed = false
    @State private var looking = false

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle(L.showWeather, isOn: $prefs.showWeather)
                    .onChange(of: prefs.showWeather) { weather.refresh(force: true) }
                Picker(L.weatherLocation, selection: $prefs.useCurrentLocation) {
                    Text(L.currentLocation).tag(true)
                    Text(L.chooseCity).tag(false)
                }
                .onChange(of: prefs.useCurrentLocation) { weather.refresh(force: true) }
                .disabled(!prefs.showWeather)
                if !prefs.useCurrentLocation {
                    HStack {
                        TextField(L.chooseCity, text: $city, prompt: Text(L.cityPlaceholder))
                            .onSubmit(lookUp)
                        if looking {
                            ProgressView().controlSize(.small)
                        } else if let place = prefs.weatherPlace, !lookupFailed {
                            Label(place.name, systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if lookupFailed {
                        Text(L.cityNotFound)
                            .foregroundStyle(.red)
                    }
                } else if weather.locationDenied {
                    Text(L.locationDenied)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.weatherFooter)
                        .foregroundStyle(.secondary)
                    if let credit = weather.credit {
                        Link(credit.label, destination: credit.legalPage)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { city = prefs.weatherPlace?.name ?? "" }
    }

    private func lookUp() {
        let query = city.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        looking = true
        Task {
            let place = await weather.lookUp(city: query)
            looking = false
            lookupFailed = place == nil
            if let place {
                prefs.weatherPlace = place
                city = place.name
                weather.refresh(force: true)
            }
        }
    }
}
