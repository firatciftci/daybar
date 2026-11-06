import Contacts
import EventKit
import Foundation
import ImageIO
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
    case me
}

@Observable
final class ContactsModel {
    static let shared = ContactsModel()

    private(set) var cards: [ContactKey: ContactCard] = [:]
    @ObservationIgnored private var pending: Set<ContactKey> = []
    @ObservationIgnored private var misses: Set<ContactKey> = []
    @ObservationIgnored private var access: Task<Bool, Never>?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    func card(for keys: Array<ContactKey>) -> ContactCard? {
        guard ![.denied, .restricted].contains(CNContactStore.authorizationStatus(for: .contacts)) else { return nil }
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

    func card(for participant: EKParticipant, email: String?, name: String?) -> ContactCard? {
        var keys: Array<ContactKey> = []
        if participant.isCurrentUser { keys.append(.me) }
        if let email, !email.isEmpty { keys.append(.email(email.lowercased())) }
        if let name, !name.isEmpty { keys.append(.name(name)) }
        return card(for: keys)
    }

    func reset() {
        cards = [:]
        misses = []
    }

    private func load(_ key: ContactKey) {
        pending.insert(key)
        Task {
            guard await ensureAccess() else {
                pending.remove(key)
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
            let request = access ?? Task { (try? await CNContactStore().requestAccess(for: .contacts)) ?? false }
            access = request
            return await request.value
        default:
            return false
        }
    }

    nonisolated private static func fetch(_ key: ContactKey) -> ContactCard? {
        let store = CNContactStore()
        let keys: Array<any CNKeyDescriptor> = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactThumbnailImageDataKey as any CNKeyDescriptor,
            CNContactImageDataKey as any CNKeyDescriptor,
            CNContactImageDataAvailableKey as any CNKeyDescriptor,
        ]
        let matches: Array<CNContact> =
            switch key {
            case .identifier(let id):
                (try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)).map { [$0] } ?? []
            case .email(let email):
                (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingEmailAddress: email), keysToFetch: keys)) ?? []
            case .name(let name):
                (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)) ?? []
            case .me:
                (try? store.unifiedMeContactWithKeys(toFetch: keys)).map { [$0] } ?? []
            }
        guard let contact = matches.first(where: \.imageDataAvailable) ?? matches.first else { return nil }
        return ContactCard(
            identifier: contact.identifier,
            name: CNContactFormatter.string(from: contact, style: .fullName),
            thumbnail: contact.imageDataAvailable ? contact.thumbnailImageData ?? contact.imageData.flatMap(downscaled) : nil
        )
    }

    nonisolated private static func downscaled(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320,
                ] as CFDictionary
            )
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
