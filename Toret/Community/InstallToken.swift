import Foundation
import Security

/// Where the install token is kept between launches.
protocol InstallTokenStore: Sendable {
    func read() -> String?
    /// True when the token is now stored.
    func write(_ token: String) -> Bool
}

/// The random code that stands for this install on the server.
///
/// There are no accounts: the server only ever sees a salted hash of this token,
/// and derives the author's handle from it the way ``AuthorHandle`` does. It has
/// to survive relaunches, or every launch would be a new "Visitante" that cannot
/// delete the reports the last one wrote.
enum InstallToken {
    /// What the server accepts: 16 to 64 characters from `[A-Za-z0-9._-]`.
    static func isValid(_ token: String) -> Bool {
        guard (16 ... 64).contains(token.utf8.count) else { return false }
        return token.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2E || byte == 0x5F || byte == 0x2D
        }
    }

    /// The stored token, or a new one saved for next time.
    ///
    /// `seed` is the install id the community store already used for its handle,
    /// so people who have seen this device's handle keep seeing the same one. If
    /// the Keychain cannot be written the token still lives for this launch, and
    /// when it came from the seed (which is kept in the community file) it is the
    /// same one next launch too.
    static func resolve(
        store: any InstallTokenStore,
        seed: String? = nil,
        generate: () -> String = { UUID().uuidString }
    ) -> String {
        if let stored = store.read(), isValid(stored) { return stored }
        let token = seed.flatMap { isValid($0) ? $0 : nil } ?? generate()
        _ = store.write(token)
        return token
    }
}

/// The Keychain, readable after the first unlock and never copied to another
/// device or a backup.
struct KeychainTokenStore: InstallTokenStore {
    var service = "br.tec.nuance.toret.install"
    var account = "token"

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func read() -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) -> Bool {
        let data = Data(token.utf8)
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
