//
//  KeychainBooleanStore.swift
//  GlanceSAT
//

import Foundation
import Security

/// Minimal Keychain helper for small persistent flags (e.g. one-time promo claims).
enum KeychainBooleanStore {
    private static let service = "com.mikihill.GlanceSAT.keychain"

    static func bool(forKey key: String) -> Bool {
        guard let data = readData(forKey: key), let byte = data.first else { return false }
        return byte == 1
    }

    static func setBool(_ value: Bool, forKey key: String) {
        let data = Data([value ? 1 : 0])
        if readData(forKey: key) != nil {
            update(data, forKey: key)
        } else {
            add(data, forKey: key)
        }
    }

    static func delete(forKey key: String) {
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func readData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func add(_ data: Data, forKey key: String) {
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func update(_ data: Data, forKey key: String) {
        let query = baseQuery(forKey: key)
        let attributes = [kSecValueData as String: data]
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
