import Foundation
import GlucoBarCore
import Security

/// SecretStore backed by the Keychain (generic passwords, one service).
///
/// Builds signed with the GlucoBar provisioning profile (Developer ID releases, and local builds
/// set up as in Config/Signing.xcconfig) keep secrets in iCloud Keychain, so they reach every Mac
/// signed in to the same Apple Account. Secrets an older build left in the login keychain move
/// there the first time they are read. Builds without the profile (ad-hoc) can't use iCloud
/// Keychain and keep using the login keychain.
struct KeychainSecretStore: SecretStore {
    var service = "dev.moti.glucobar"

    struct KeychainError: Error, LocalizedError {
        let status: OSStatus
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)" }
    }

    /// Whether this build may use the data protection keychain, which iCloud Keychain needs. It
    /// requires an application-identifier entitlement, which only a provisioning profile grants.
    static let syncAvailable: Bool = {
        var q = KeychainSecretStore().syncedQuery("dev.moti.glucobar.probe")
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) != errSecMissingEntitlement
    }()

    private func syncedQuery(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: true]
    }

    /// The file-based login keychain: not synced.
    private func loginQuery(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    func secret(named name: String) throws -> String? {
        guard Self.syncAvailable else { return try read(loginQuery(name)) }
        if let value = try read(syncedQuery(name)) { return value }
        guard let legacy = try read(loginQuery(name)) else { return nil }
        try add(legacy, syncedQuery(name))
        try delete(loginQuery(name))
        return legacy
    }

    func setSecret(_ value: String?, named name: String) throws {
        if Self.syncAvailable {
            try delete(syncedQuery(name))
        }
        try delete(loginQuery(name))
        guard let value else { return }
        try add(value, Self.syncAvailable ? syncedQuery(name) : loginQuery(name))
    }

    private func read(_ query: [String: Any]) throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    private func add(_ value: String, _ query: [String: Any]) throws {
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        if q[kSecAttrSynchronizable as String] != nil {
            // Synced items can't be device-only; readable while locked so polling keeps working.
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Another Mac synced the same secret in meanwhile; overwrite it.
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
