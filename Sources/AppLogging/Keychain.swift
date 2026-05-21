// Keychain — per NEXT_STEPS_MAY_20_2026.md §9.4.
//
// Native SecItem wrapper. Used for our own secrets (e.g. future DPoP keys
// and Share Extension shared state). ATProtoKit's session tokens are stored
// via its built-in AppleSecureKeychain — don't duplicate that here.
//
// Accessibility class: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
// Background refresh still works after first unlock; the secret never
// syncs to iCloud Keychain; a restored device backup forces re-login.

import Foundation
import Security

public enum Keychain {
    public enum Error: Swift.Error { case status(OSStatus) }

    public static func set(_ data: Data, account: String, service: String) throws {
        let q: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:        data,
        ]
        SecItemDelete(q as CFDictionary)
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else { throw Error.status(s) }
    }

    public static func data(account: String, service: String) throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess else { throw Error.status(s) }
        return item as? Data
    }

    public static func delete(account: String, service: String) throws {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        let s = SecItemDelete(q as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw Error.status(s) }
    }
}
