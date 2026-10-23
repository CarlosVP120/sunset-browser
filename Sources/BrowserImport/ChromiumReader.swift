import Foundation
import CommonCrypto
import Security
import BrowserCore
import BrowserEngine

/// Navegadores basados en Chromium (Chrome, Arc, Brave, Edge): todos guardan sus datos igual.
public struct ChromiumBrowser: Sendable {
    /// Carpeta de datos de usuario (la que contiene `Local State` y los perfiles).
    public var userDataDirectory: URL
    /// Servicio del Llavero donde el navegador guarda la clave con la que cifra contraseñas y cookies.
    public var keychainService: String

    public init(userDataDirectory: URL, keychainService: String) {
        self.userDataDirectory = userDataDirectory
        self.keychainService = keychainService
    }

    /// Perfiles del navegador (carpeta y nombre visible), empezando por el predeterminado.
    public func profiles() -> [(folder: String, name: String)] {
        let localState = userDataDirectory.appending(path: "Local State")
        guard let data = try? Data(contentsOf: localState),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any], !cache.isEmpty
        else {
            return FileManager.default.fileExists(atPath: userDataDirectory.appending(path: "Default").path)
                ? [("Default", "Predeterminado")] : []
        }
        return cache.keys.sorted { a, b in a == "Default" || (b != "Default" && a < b) }.map { folder in
            ((folder), ((cache[folder] as? [String: Any])?["name"] as? String) ?? folder)
        }
    }
}

/// Lee un perfil de un navegador Chromium. Solo lee (sobre copias): el otro navegador no cambia.
struct ChromiumReader {
    let browser: ChromiumBrowser
    let profile: String

    private var directory: URL { browser.userDataDirectory.appending(path: profile) }

    // MARK: Marcadores

    func bookmarks() throws -> ImportedBookmarks {
        let data = try Data(contentsOf: directory.appending(path: "Bookmarks"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any]
        else { throw SQLiteReader.ReadError.unreadable }
        return Self.parseBookmarks(roots: roots)
    }

    static func parseBookmarks(roots: [String: Any]) -> ImportedBookmarks {
        func url(_ node: [String: Any]) -> ImportedBookmark? {
            guard node["type"] as? String == "url", let string = node["url"] as? String,
                  let url = URL(string: string), url.scheme == "http" || url.scheme == "https" else { return nil }
            return ImportedBookmark(title: node["name"] as? String ?? url.host() ?? string, url: url)
        }
        func flatten(_ node: [String: Any]) -> [ImportedBookmark] {
            (node["children"] as? [[String: Any]] ?? []).flatMap { child in
                url(child).map { [$0] } ?? flatten(child)
            }
        }

        var result = ImportedBookmarks()
        // Barra de marcadores: los enlaces sueltos quedan fijados y cada carpeta, como carpeta.
        if let bar = roots["bookmark_bar"] as? [String: Any] {
            for child in bar["children"] as? [[String: Any]] ?? [] {
                if let bookmark = url(child) {
                    result.loose.append(bookmark)
                } else if child["type"] as? String == "folder" {
                    let bookmarks = flatten(child)
                    if !bookmarks.isEmpty {
                        result.folders.append(ImportedFolder(name: child["name"] as? String ?? "Carpeta", bookmarks: bookmarks))
                    }
                }
            }
        }
        for (key, name) in [("other", "Otros marcadores"), ("synced", "Marcadores del móvil")] {
            if let node = roots[key] as? [String: Any] {
                let bookmarks = flatten(node)
                if !bookmarks.isEmpty { result.folders.append(ImportedFolder(name: name, bookmarks: bookmarks)) }
            }
        }
        return result
    }

    // MARK: Historial

    func history(limit: Int = 5000) throws -> [HistoryEntry] {
        let rows = try SQLiteReader.query("""
            SELECT url, title, visit_count, last_visit_time FROM urls
            WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT \(limit)
            """, in: directory.appending(path: "History"))
        return rows.compactMap { row in
            guard let string = row["url"]?.string, let url = URL(string: string),
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            return HistoryEntry(url: url, title: row["title"]?.string ?? "",
                                visitCount: Int(row["visit_count"]?.int ?? 1),
                                lastVisit: Self.date(fromWebKitMicroseconds: row["last_visit_time"]?.int ?? 0))
        }
    }

    /// Chromium cuenta el tiempo en microsegundos desde el 1 de enero de 1601.
    static func date(fromWebKitMicroseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1_000_000 - 11_644_473_600)
    }

    // MARK: Contraseñas

    func credentials(key: Data) throws -> [Credential] {
        let rows = try SQLiteReader.query("""
            SELECT origin_url, username_value, password_value, date_created FROM logins
            WHERE blacklisted_by_user = 0
            """, in: directory.appending(path: "Login Data"))
        return rows.compactMap { row in
            guard let origin = row["origin_url"]?.string.flatMap(URL.init(string:)),
                  let encrypted = row["password_value"]?.data,
                  let plain = ChromiumCrypto.decrypt(encrypted, key: key),
                  let password = String(data: plain, encoding: .utf8), !password.isEmpty
            else { return nil }
            return Credential(url: origin, username: row["username_value"]?.string ?? "", password: password,
                              created: Self.date(fromWebKitMicroseconds: row["date_created"]?.int ?? 0))
        }
    }

    // MARK: Cookies

    func cookies(key: Data) throws -> [HTTPCookie] {
        // En macOS están en el perfil; las versiones nuevas las mueven a `Network/`.
        let candidates = [directory.appending(path: "Cookies"), directory.appending(path: "Network/Cookies")]
        guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SQLiteReader.ReadError.notFound
        }
        // Desde la versión 24 de la base, cada valor descifrado empieza con el hash del dominio (32 bytes).
        let version = (try? SQLiteReader.query("SELECT value FROM meta WHERE key = 'version'", in: file))?
            .first?["value"]?.string.flatMap(Int.init) ?? 0
        let rows = try SQLiteReader.query("""
            SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite
            FROM cookies
            """, in: file)
        let now = Date()
        return rows.compactMap { row in
            guard let host = row["host_key"]?.string, let name = row["name"]?.string else { return nil }
            var value = row["value"]?.string ?? ""
            if value.isEmpty, let encrypted = row["encrypted_value"]?.data, !encrypted.isEmpty {
                guard var plain = ChromiumCrypto.decrypt(encrypted, key: key) else { return nil }
                if version >= 24, plain.count >= 32 { plain = plain.dropFirst(32) }
                guard let text = String(data: plain, encoding: .utf8) else { return nil }
                value = text
            }
            let expiresRaw = row["expires_utc"]?.int ?? 0
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host, .name: name, .value: value, .path: row["path"]?.string ?? "/",
            ]
            if expiresRaw > 0 {
                let expires = Self.date(fromWebKitMicroseconds: expiresRaw)
                guard expires > now else { return nil } // ya caducada
                properties[.expires] = expires
            } else {
                properties[.discard] = "TRUE"
            }
            if row["is_secure"]?.int == 1 { properties[.secure] = "TRUE" }
            if row["is_httponly"]?.int == 1 { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            switch row["samesite"]?.int {
            case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
            case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
            default: break
            }
            return HTTPCookie(properties: properties)
        }
    }
}

/// Cifrado de Chromium en macOS: AES-128-CBC con una clave derivada (PBKDF2) de la contraseña
/// que el navegador guarda en el Llavero ("Chrome Safe Storage", "Arc Safe Storage"…).
enum ChromiumCrypto {
    enum KeyError: Error {
        case denied
        case notFound
    }

    /// Pide al Llavero la contraseña del otro navegador. macOS le pregunta al usuario si lo permite.
    static func storageKey(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let secret = result as? Data else { throw KeyError.notFound }
            return derivedKey(from: secret)
        case errSecItemNotFound:
            throw KeyError.notFound
        default:
            throw KeyError.denied
        }
    }

    static func derivedKey(from secret: Data) -> Data {
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        secret.withUnsafeBytes { secretBytes in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                secretBytes.baseAddress?.assumingMemoryBound(to: CChar.self), secret.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                &key, key.count
            )
        }
        return Data(key)
    }

    private static let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)

    /// Descifra un valor con el prefijo "v10". Devuelve nil si no se puede.
    static func decrypt(_ value: Data, key: Data) -> Data? {
        guard value.count > 3, value.prefix(3) == Data("v10".utf8) else { return nil }
        return crypt(CCOperation(kCCDecrypt), Data(value.dropFirst(3)), key: key)
    }

    /// Cifra como lo hace Chromium (para las pruebas).
    static func encrypt(_ value: Data, key: Data) -> Data? {
        crypt(CCOperation(kCCEncrypt), value, key: key).map { Data("v10".utf8) + $0 }
    }

    private static func crypt(_ operation: CCOperation, _ input: Data, key: Data) -> Data? {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { inputBytes in
                CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv,
                        inputBytes.baseAddress, input.count,
                        &output, output.count, &written)
            }
        }
        return status == kCCSuccess ? Data(output.prefix(written)) : nil
    }
}
