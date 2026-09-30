import CompanionCore
import Contacts
import Foundation

struct ContactRecord: Sendable, Equatable {
    let id: String
    let name: String
}

struct ChannelRecord: Sendable, Equatable {
    let kind: MentionChannel.Kind
    let label: String?
    let value: String
}

/// The address book under `SystemContacts`, narrowed to the three things the
/// selector may do. A fake stands in for it in tests: the real store shows a
/// system dialog and needs the usage description only the bundle carries.
protocol ContactsBackend: Sendable {
    func status() -> ContactsAccess
    func requestAccess() async throws -> Bool
    func names(matching query: String) throws -> [ContactRecord]
    func channels(ofContact id: String) throws -> [ChannelRecord]
}

/// 16m-7: the `@` selector's contacts. Privacy contract (spec 16m §9):
/// permission is asked only through `requestAccess()`, which the selector
/// calls the first time she types `@`; a search reads names of the people
/// that match what she typed, never the book; a contact's email and phone
/// are read only when she opens that one contact; nothing here is logged
/// with a name, a query or an identifier.
public struct SystemContacts: ContactsProviding {
    /// Own value: a contact with more ways to reach it than this is a
    /// company switchboard; the list has to stay one glance long.
    static let maxChannels = 6

    let backend: any ContactsBackend

    public init() {
        self.init(backend: StoreBackend())
    }

    init(backend: any ContactsBackend) {
        self.backend = backend
    }

    public func access() -> ContactsAccess {
        backend.status()
    }

    public func requestAccess() async -> Bool {
        switch backend.status() {
        case .granted: return true
        // The system shows no second dialog after a denial; asking again
        // would only look like it worked.
        case .denied: return false
        case .notDetermined:
            do {
                return try await backend.requestAccess()
            } catch {
                Log.app("contacts: the access request failed")
                return false
            }
        }
    }

    public func search(_ query: String, limit: Int) async -> [MentionCandidate] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // No text, no search: the selector never lists the book.
        guard backend.status() == .granted, !text.isEmpty else { return [] }
        do {
            let capped = min(max(limit, 1), MentionRanking.maxRows)
            return try backend.names(matching: text)
                .compactMap { MentionCandidate(id: $0.id, kind: .contact, name: $0.name) }
                .prefix(capped)
                .map { $0 }
        } catch {
            Log.app("contacts: the search failed")
            return []
        }
    }

    public func channels(ofContact id: String) async -> [MentionChannel] {
        guard backend.status() == .granted else { return [] }
        do {
            return try backend.channels(ofContact: id)
                .compactMap { MentionChannel(kind: $0.kind, label: $0.label, value: $0.value) }
                .prefix(Self.maxChannels)
                .map { $0 }
        } catch {
            Log.app("contacts: could not read a contact's channels")
            return []
        }
    }
}

/// The system framework. Exercised live only.
private struct StoreBackend: ContactsBackend {
    // One store per call: the class is not Sendable, and creating one is cheap.
    private var store: CNContactStore { CNContactStore() }

    func status() -> ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        // Limited access still answers fetches for the contacts she shared.
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    // HACK: the store returns every match before the selector cuts it to
    // eight. Fine at address-book sizes; when a one-letter query is slow on a
    // huge book, enumerate with an early stop instead.
    func names(matching query: String) throws -> [ContactRecord] {
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        return try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
            .compactMap { contact in
                CNContactFormatter.string(from: contact, style: .fullName).map { ContactRecord(id: contact.identifier, name: $0) }
            }
    }

    func channels(ofContact id: String) throws -> [ChannelRecord] {
        let keys: [CNKeyDescriptor] = [CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
        guard let contact = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: [id]), keysToFetch: keys).first
        else { return [] }
        let emails = contact.emailAddresses.map {
            ChannelRecord(kind: .email, label: $0.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)), value: $0.value as String)
        }
        let phones = contact.phoneNumbers.map {
            ChannelRecord(kind: .phone, label: $0.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)), value: $0.value.stringValue)
        }
        return emails + phones
    }
}
