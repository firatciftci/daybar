import AppKit
import Contacts
import CoreLocation
import EventKit
import Observation

enum PermissionKind: CaseIterable, Identifiable {
    case calendars
    case reminders
    case contacts
    case location

    var id: Self { self }

    var settingsURL: URL? {
        let anchor =
            switch self {
            case .calendars: "Privacy_Calendars"
            case .reminders: "Privacy_Reminders"
            case .contacts: "Privacy_Contacts"
            case .location: "Privacy_LocationServices"
            }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum PermissionStatus {
    case undetermined
    case granted
    case denied
}

@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    private(set) var requesting: PermissionKind?
    @ObservationIgnored private let location = CLLocationManager()

    private init() {
        refresh()
    }

    func status(of kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .undetermined
    }

    func refresh() {
        let current: [PermissionKind: PermissionStatus] = [
            .calendars: Self.status(EKEventStore.authorizationStatus(for: .event)),
            .reminders: Self.status(EKEventStore.authorizationStatus(for: .reminder)),
            .contacts: Self.status(CNContactStore.authorizationStatus(for: .contacts)),
            .location: Self.status(location.authorizationStatus),
        ]
        if current != statuses {
            let contactsChanged = statuses[.contacts] != nil && statuses[.contacts] != current[.contacts]
            statuses = current
            if contactsChanged { ContactsModel.shared.reset() }
            CalendarStore.shared.refreshAccess()
        }
    }

    func request(_ kind: PermissionKind) async {
        requesting = kind
        switch kind {
        case .calendars:
            _ = try? await CalendarStore.shared.ek.requestFullAccessToEvents()
        case .reminders:
            _ = try? await CalendarStore.shared.ek.requestFullAccessToReminders()
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .location:
            WeatherModel.shared.requestLocationAccess()
        }
        requesting = nil
        refresh()
    }

    func openSettings(for kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    private static func status(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    private static func status(_ status: CNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .limited: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    private static func status(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }
}
