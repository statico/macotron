import CQuickJS
import Contacts
import Foundation
import MacotronEngine

enum ContactsList {
    static func matches(_ query: String, name: String, emails: [String], phones: [String], organization: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        let hay = ([name, organization] + emails + phones).joined(separator: " ")
        return hay.localizedStandardContains(q)
    }

    static func row(_ contact: CNContact) -> [String: Any] {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        return [
            "id": contact.identifier,
            "name": name,
            "first": contact.givenName,
            "last": contact.familyName,
            "organization": contact.organizationName,
            "emails": contact.emailAddresses.map { $0.value as String },
            "phones": contact.phoneNumbers.map { $0.value.stringValue },
        ]
    }
}

@MainActor
public final class ContactsModule: NativeModule {
    public let name = "contacts"

    /// One store for the app: Contacts ties the granted access to the store
    /// that asked, and the enumeration below runs it off the main thread.
    private nonisolated(unsafe) static let store = CNContactStore()
    private static var requestedAccess = false
    private nonisolated(unsafe) static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let contacts = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, contacts, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return ContactsModule.fetchPromise(ctx, query: "")
        }, "list", 0))

        JS_SetPropertyStr(ctx, contacts, "search", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            var query = ""
            if let argv, argc >= 1 {
                query = JSBridge.toString(ctx, argv[0]) ?? ""
            }
            return ContactsModule.fetchPromise(ctx, query: query)
        }, "search", 1))

        JS_SetPropertyStr(ctx, macotron, "contacts", contacts)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    /// The permission prompt has to be raised on the main thread; only the
    /// enumeration behind it moves off.
    private static func fetchPromise(_ ctx: OpaquePointer, query: String) -> JSValue {
        guard Engine.isDryRun(ctx) || authorized() else {
            return JSBridge.promise(ctx) { .value([Any]()) }
        }
        return JSBridge.promise(ctx, dryRun: [Any]()) { .value(fetch(query: query)) }
    }

    private static func authorized() -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            if !requestedAccess {
                requestedAccess = true
                store.requestAccess(for: .contacts) { _, _ in }
            }
            return false
        case .denied, .restricted:
            return false
        default:
            return true
        }
    }

    private nonisolated static func fetch(query: String) -> [Any] {
        let request = CNContactFetchRequest(keysToFetch: keys)
        var rows: [Any] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            let row = ContactsList.row(contact)
            let name = row["name"] as? String ?? ""
            let emails = row["emails"] as? [String] ?? []
            let phones = row["phones"] as? [String] ?? []
            let org = row["organization"] as? String ?? ""
            if ContactsList.matches(query, name: name, emails: emails, phones: phones, organization: org) {
                rows.append(row)
            }
        }
        return rows
    }
}
