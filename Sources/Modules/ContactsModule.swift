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

    private static let store = CNContactStore()
    private static var requestedAccess = false
    private static let keys: [CNKeyDescriptor] = [
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
            if Engine.isDryRun(ctx) { return JSBridge.newArray(ctx, []) }
            return JSBridge.newArray(ctx, ContactsModule.fetch(query: ""))
        }, "list", 0))

        JS_SetPropertyStr(ctx, contacts, "search", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return JSBridge.newArray(ctx, []) }
            var query = ""
            if let argv, argc >= 1 {
                query = JSBridge.toString(ctx, argv[0]) ?? ""
            }
            return JSBridge.newArray(ctx, ContactsModule.fetch(query: query))
        }, "search", 1))

        JS_SetPropertyStr(ctx, macotron, "contacts", contacts)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    private static func fetch(query: String) -> [Any] {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            if !requestedAccess {
                requestedAccess = true
                store.requestAccess(for: .contacts) { _, _ in }
            }
            return []
        case .denied, .restricted:
            return []
        default:
            break
        }

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
