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
    case participant(String)
    case me
}

private nonisolated struct PredicateBox: @unchecked Sendable {
    let predicate: NSPredicate
}

@Observable
final class ContactsModel {
    static let shared = ContactsModel()

    private(set) var cards: [ContactKey: ContactCard] = [:]
    @ObservationIgnored private var pending: Set<ContactKey> = []
    @ObservationIgnored private var misses: Set<ContactKey> = []
    @ObservationIgnored private var predicates: [String: NSPredicate] = [:]
    @ObservationIgnored private var access: Task<Bool, Never>?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    func card(for keys: Array<ContactKey>) -> ContactCard? {
        guard !DemoData.isEnabled, ![.denied, .restricted].contains(CNContactStore.authorizationStatus(for: .contacts)) else { return nil }
        if let card = keys.lazy.compactMap({ self.cards[$0] }).first(where: { $0.thumbnail != nil }) {
            return card
        }
        for key in keys where cards[key] == nil && !misses.contains(key) && !pending.contains(key) {
            load(key)
        }
        return keys.lazy.compactMap { self.cards[$0] }.first
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
        let url = participant.url.absoluteString
        predicates[url] = participant.contactPredicate
        keys.append(.participant(url))
        if let email, !email.isEmpty { keys.append(.email(email.lowercased())) }
        if let name, !name.isEmpty { keys.append(.name(name)) }
        return card(for: keys)
    }

    func reset() {
        cards = [:]
        misses = []
        predicates = [:]
    }

    private func load(_ key: ContactKey) {
        pending.insert(key)
        Task {
            guard await ensureAccess() else {
                pending.remove(key)
                return
            }
            let predicate: PredicateBox? =
                if case .participant(let url) = key { predicates[url].map(PredicateBox.init) } else { nil }
            let card = await Task.detached(priority: .utility) { Self.fetch(key, predicate: predicate) }.value
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

    nonisolated private static func fetch(_ key: ContactKey, predicate: PredicateBox?) -> ContactCard? {
        let store = CNContactStore()
        let keys: Array<any CNKeyDescriptor> = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactNicknameKey as any CNKeyDescriptor,
            CNContactThumbnailImageDataKey as any CNKeyDescriptor,
            CNContactImageDataKey as any CNKeyDescriptor,
        ]
        let matches: Array<CNContact> =
            switch key {
            case .identifier(let id):
                (try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)).map { [$0] } ?? []
            case .email(let email):
                (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingEmailAddress: email), keysToFetch: keys)) ?? []
            case .name(let name):
                nameMatches(name, in: store, keys: keys)
            case .participant:
                predicate.flatMap { try? store.unifiedContacts(matching: $0.predicate, keysToFetch: keys) } ?? []
            case .me:
                (try? store.unifiedMeContactWithKeys(toFetch: keys)).map { [$0] } ?? []
            }
        let photographed = matches.lazy.compactMap { contact in photo(of: contact).map { (contact, $0) } }.first
        guard let contact = photographed?.0 ?? matches.first else { return nil }
        return ContactCard(
            identifier: contact.identifier,
            name: CNContactFormatter.string(from: contact, style: .fullName),
            thumbnail: photographed?.1
        )
    }

    nonisolated private static func nameMatches(
        _ raw: String, in store: CNContactStore, keys: Array<any CNKeyDescriptor>
    ) -> Array<CNContact> {
        let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count == 2 ? "\(parts[1]) \(parts[0])" : raw
        let exact = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)) ?? []
        if !exact.isEmpty { return exact }
        let tokens = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, tokens.count > 1 else { return [] }
        let candidates =
            (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: first), keysToFetch: keys)) ?? []
        let rest = Set(tokens.dropFirst().map { $0.lowercased() })
        let given = candidates.filter { $0.givenName.caseInsensitiveCompare(first) == .orderedSame }
        let strong = given.filter { rest.contains($0.familyName.lowercased()) || rest.contains($0.nickname.lowercased()) }
        if !strong.isEmpty { return strong }
        let loose = given.filter(\.familyName.isEmpty)
        return loose.count == 1 ? loose : []
    }

    nonisolated private static func photo(of contact: CNContact) -> Data? {
        guard let data = contact.thumbnailImageData ?? contact.imageData, !data.isEmpty else { return nil }
        return data.count > 48_000 ? downscaled(data) ?? data : data
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
