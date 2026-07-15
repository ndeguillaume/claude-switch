import Foundation
import Security

public struct KeychainItem: Equatable {
    public let account: String
    public let data: Data

    public init(account: String, data: Data) {
        self.account = account
        self.data = data
    }
}

public protocol KeychainClient {
    func read(service: String) throws -> KeychainItem?
    func upsert(service: String, item: KeychainItem) throws
    func delete(service: String) throws
}

public final class SystemKeychainClient: KeychainClient {
    public init() {}

    public func read(service: String) throws -> KeychainItem? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data
        else {
            throw SwitchError.keychain(status)
        }
        let account = attributes[kSecAttrAccount as String] as? String ?? ""
        return KeychainItem(account: account, data: data)
    }

    public func upsert(service: String, item: KeychainItem) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let update: [String: Any] = [
            kSecAttrAccount as String: item.account,
            kSecValueData as String: item.data,
        ]
        // SecItemUpdate first: preserves the ACL of the item created by the claude CLI,
        // so claude won't prompt for authorization again after a switch.
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecAttrAccount as String] = item.account
            add[kSecValueData as String] = item.data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SwitchError.keychain(status) }
    }

    public func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwitchError.keychain(status)
        }
    }
}
