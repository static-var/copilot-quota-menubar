import CommonCrypto
import Foundation
import Security
import SQLite3

struct VSCodeAuthTokenProvider: AuthTokenProvider {
    private let productNames: [String] = Self.loadProductNames()

    func fetchToken() throws -> GitHubAuthToken {
        var sawDatabase = false
        var lastError: Error?

        for productName in productNames {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dbURL = home
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(productName)
                .appendingPathComponent("User/globalStorage/state.vscdb")

            guard FileManager.default.fileExists(atPath: dbURL.path) else { continue }
            sawDatabase = true

            do {
                if let token = try fetchToken(productName: productName, dbURL: dbURL) {
                    return token
                }
            } catch {
                // If one product profile fails, try the next.
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw SimpleError(message: sawDatabase ? "Not signed in via VS Code" : "VS Code auth data not found")
    }

    private static func loadProductNames() -> [String] {
        if let raw = ProcessInfo.processInfo.environment["COPILOT_QUOTA_VSCODE_PRODUCTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        {
            let parsed = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }

        // Defaults cover the common macOS application support dirs.
        return ["Code - Insiders", "Code", "VSCodium"]
    }

    private func fetchToken(productName: String, dbURL: URL) throws -> GitHubAuthToken? {
        let key = #"secret://{"extensionId":"vscode.github-authentication","key":"github.auth"}"#
        guard let encryptedJSON = try SQLiteKeyValueStore(dbURL: dbURL).readValue(forKey: key) else { return nil }

        let encryptedBuffer = try JSONDecoder().decode(NodeBufferJSON.self, from: Data(encryptedJSON.utf8))
        let encrypted = Data(encryptedBuffer.data)

        let safeStoragePassword = try Keychain.readGenericPassword(service: "\(productName) Safe Storage")
        let keyData = try PBKDF2.deriveKeySHA1(password: safeStoragePassword, salt: Data("saltysalt".utf8), rounds: 1003, keyByteCount: 16)
        let plaintext = try V10.decrypt(encrypted: encrypted, key: keyData)

        let sessions = try JSONDecoder().decode([GitHubAuthSession].self, from: plaintext)
        guard let session = sessions.first(where: { !$0.accessToken.isEmpty }) else { return nil }

        return GitHubAuthToken(token: session.accessToken, source: "VS Code (\(productName))")
    }
}

private struct NodeBufferJSON: Codable {
    // {"type":"Buffer","data":[...]}
    let data: [UInt8]
}

private struct GitHubAuthSession: Codable {
    let accessToken: String
}

private enum Keychain {
    static func readGenericPassword(service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw SimpleError(message: "Missing keychain item: \(service)")
        }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw SimpleError(message: "Invalid keychain data: \(service)")
        }
        return password.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PBKDF2 {
    static func deriveKeySHA1(password: String, salt: Data, rounds: Int, keyByteCount: Int) throws -> Data {
        var derivedKey = Data(repeating: 0, count: keyByteCount)
        let passwordBytes = Array(password.utf8)

        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes,
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    UInt32(rounds),
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyByteCount
                )
            }
        }

        guard status == kCCSuccess else {
            throw SimpleError(message: "PBKDF2 failed")
        }
        return derivedKey
    }
}

private enum V10 {
    static func decrypt(encrypted: Data, key: Data) throws -> Data {
        let prefix = Data([0x76, 0x31, 0x30]) // "v10"
        guard encrypted.starts(with: prefix) else {
            throw SimpleError(message: "Unsupported VS Code secret format")
        }

        let iv = Data(repeating: 0x20, count: 16) // 16 spaces
        let ciphertext = encrypted.dropFirst(3)

        let outCapacity = ciphertext.count + kCCBlockSizeAES128
        var out = Data(repeating: 0, count: outCapacity)
        var outLen: size_t = 0

        let status = out.withUnsafeMutableBytes { outBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    ciphertext.withUnsafeBytes { ctBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ctBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLen
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw SimpleError(message: "Secret decrypt failed")
        }

        return out.prefix(outLen)
    }
}

private final class SQLiteKeyValueStore {
    private let dbURL: URL
    private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(dbURL: URL) {
        self.dbURL = dbURL
    }

    func readValue(forKey key: String) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SimpleError(message: "Failed to open VS Code database")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            throw SimpleError(message: "Failed to query VS Code database")
        }
        defer { sqlite3_finalize(stmt) }

        _ = key.withCString { cStr in
            sqlite3_bind_text(stmt, 1, cStr, -1, sqliteTransientDestructor)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }
}
