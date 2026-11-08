import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        Task { [weak self] in self?.view.window?.makeFirstResponder(nil) }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var opening = false
    private let tabs: SettingsTabs

    private init() {
        let tabs = SettingsTabs()
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
                    .environment(SettingsRoute.shared)
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
        add(L.tabAdvanced, symbol: "gearshape.2", AdvancedPane())
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.tabs = tabs
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func show(_ destination: SettingsDestination = .lastPage) {
        guard let window else { return }
        if destination != .lastPage, let index = tabs.tabViewItems.firstIndex(where: { $0.label == L.tabCalendars }) {
            tabs.selectedTabViewItemIndex = index
        }
        if destination == .newCalendarSet {
            SettingsRoute.shared.wantsNewSet = true
        }
        if !window.isVisible { window.center() }
        opening = true
        window.presentInFront()
        clearFocus()
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            opening = false
        }
    }

    func windowDidBecomeKey(_: Notification) {
        if opening { clearFocus() }
    }

    private func clearFocus() {
        Task { [weak self] in
            guard let window = self?.window else { return }
            if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp, event.window === window {
                return
            }
            window.makeFirstResponder(nil)
        }
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

private struct AdvancedPane: View {
    @Environment(CalendarStore.self) private var store
    @Environment(WeatherModel.self) private var weather
    @State private var confirming = false
    @State private var restored = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ZStack(alignment: .trailing) {
                        if restored {
                            Label(L.restoreDefaultsDone, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        } else {
                            Button(L.restoreDefaultsButton) { confirming = true }
                                .transition(.opacity)
                        }
                    }
                } label: {
                    Text(L.restoreDefaultsTitle)
                    Text(L.restoreDefaultsDetail)
                }
            }
        }
        .formStyle(.grouped)
        .alert(L.restoreDefaultsAlertTitle, isPresented: $confirming) {
            Button(L.restoreDefaultsConfirm, role: .destructive, action: restore)
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(L.restoreDefaultsAlertMessage)
        }
    }

    private func restore() {
        Preferences.shared.restoreDefaults()
        KeyboardShortcuts.reset(.togglePanel)
        store.reload()
        weather.refresh(force: true)
        withAnimation(Motion.fade) { restored = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(Motion.fade) { restored = false }
        }
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
                Toggle(L.showNextEvent, isOn: $prefs.showNextEvent)
                Picker(L.nextEventWithin, selection: $prefs.nextEventMinutes) {
                    ForEach([15, 30, 60, 180], id: \.self) { minutes in
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))).tag(minutes)
                    }
                    Text(L.restOfDay).tag(0)
                }
                .disabled(!prefs.showNextEvent)
            } footer: {
                Text(L.nextEventFooter)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
