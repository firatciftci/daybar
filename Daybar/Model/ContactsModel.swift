import Contacts
import Observation

nonisolated struct ContactCard: Hashable, Sendable {
    let identifier: String
    let name: String?
    let thumbnail: Data?

    var url: URL? { URL(string: "addressbook://\(identifier)") }
}

nonisolated enum ContactKey: Hashable, Sendable {
    case identifier(String)
    case email(String)
    case name(String)
}

@Observable
final class ContactsModel {
    static let shared = ContactsModel()

    private(set) var cards: [ContactKey: ContactCard] = [:]
    @ObservationIgnored private var pending: Set<ContactKey> = []
    @ObservationIgnored private var misses: Set<ContactKey> = []
    @ObservationIgnored private var requested = false

    func card(for keys: Array<ContactKey>) -> ContactCard? {
        for key in keys {
            if let card = cards[key] { return card }
        }
        for key in keys where !misses.contains(key) && !pending.contains(key) {
            load(key)
        }
        return nil
    }

    func card(forBirthday birthday: Birthday) -> ContactCard? {
        var keys: Array<ContactKey> = []
        if let id = birthday.contactID { keys.append(.identifier(id)) }
        keys.append(.name(birthday.name))
        return card(for: keys)
    }

    func card(forEmail email: String?) -> ContactCard? {
        guard let email, !email.isEmpty else { return nil }
        return card(for: [.email(email.lowercased())])
    }

    private func load(_ key: ContactKey) {
        pending.insert(key)
        Task {
            guard await ensureAccess() else {
                pending.remove(key)
                misses.insert(key)
                return
            }
            let card = await Task.detached(priority: .utility) { Self.fetch(key) }.value
            pending.remove(key)
            if let card {
                cards[key] = card
            } else {
                misses.insert(key)
            }
        }
    }

    private func ensureAccess() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            guard !requested else { return false }
            requested = true
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            if granted { misses.removeAll() }
            return granted
        default:
            return false
        }
    }

    nonisolated private static func fetch(_ key: ContactKey) -> ContactCard? {
        let store = CNContactStore()
        let keys: Array<any CNKeyDescriptor> = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactThumbnailImageDataKey as any CNKeyDescriptor,
            CNContactImageDataAvailableKey as any CNKeyDescriptor,
        ]
        let contact: CNContact? =
            switch key {
            case .identifier(let id):
                try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)
            case .email(let email):
                try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingEmailAddress: email), keysToFetch: keys).first
            case .name(let name):
                try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys).first
            }
        guard let contact else { return nil }
        return ContactCard(
            identifier: contact.identifier,
            name: CNContactFormatter.string(from: contact, style: .fullName),
            thumbnail: contact.imageDataAvailable ? contact.thumbnailImageData : nil
        )
    }
}
