import Foundation
import CryptoKit
import Observation
import Security

/// Una contraseña guardada para un sitio.
public struct Credential: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var username: String
    public var password: String
    public var created: Date

    public init(id: UUID = UUID(), url: URL, username: String, password: String, created: Date = Date()) {
        self.id = id
        self.url = url
        self.username = username
        self.password = password
        self.created = created
    }

    /// Dominio sin "www.".
    public var host: String {
        let host = url.host()?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Qué tan bien sirve una contraseña para una página, de más a menos.
    public enum Match: Int, Comparable, Sendable {
        /// Mismo sitio en un dominio público: la de accounts.google.com en mail.google.com.
        case sameSite
        /// Mismo origen: esquema, dominio y puerto.
        case sameOrigin

        public static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// ¿Sirve esta contraseña en `page`? Como Chrome (y Arc): mismo origen, o mismo sitio en
    /// dominios públicos con el mismo puerto. `localhost` y las IP solo valen con el origen exacto
    /// (cada proyecto local vive en su puerto). Una contraseña de http sirve en https, no al revés.
    public func match(for page: URL) -> Match? {
        guard let pageScheme = page.scheme?.lowercased(), let scheme = url.scheme?.lowercased(),
              pageScheme == scheme || (scheme == "http" && pageScheme == "https"),
              let pageHost = page.host()?.lowercased(), !pageHost.isEmpty,
              // Sin puerto escrito, ambos usan el de su esquema (80 en http, 443 en https).
              Self.port(of: page) == Self.port(of: url) || (page.port == nil && url.port == nil)
        else { return nil }
        let other = pageHost.hasPrefix("www.") ? String(pageHost.dropFirst(4)) : pageHost
        if other == host { return .sameOrigin }
        guard !Self.isLocalOrIP(other), !Self.isLocalOrIP(host), Self.site(of: other) == Self.site(of: host) else { return nil }
        return .sameSite
    }

    /// Puerto efectivo (el de la dirección o el del esquema).
    static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }

    /// localhost, *.localhost o una dirección IP: aquí no hay "sitio" que compartir.
    static func isLocalOrIP(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost") || host.contains(":")
            || host.split(separator: ".").allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Dominio "registrable" aproximado: los dos últimos niveles (tres en dominios como .com.mx).
    static func site(of host: String) -> String {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        let secondLevel = ["com", "co", "org", "net", "gob", "gov", "edu", "ac"]
        let take = secondLevel.contains(String(labels[labels.count - 2])) && labels.last!.count == 2 ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }
}

/// Las contraseñas de Sunset. Se guardan en un archivo cifrado (AES-GCM, 256 bits); la clave vive
/// en el Llavero de macOS ("Sunset Browser Safe Storage"), como hace Chrome. No se cargan hasta
/// que hacen falta (autorrellenar, importar o verlas en la Librería).
@MainActor
@Observable
public final class PasswordVault {
    public private(set) var credentials: [Credential] = []
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let keyProvider: () throws -> SymmetricKey

    public init(fileURL: URL = PasswordVault.standardFileURL,
                keyProvider: @escaping () throws -> SymmetricKey = { try PasswordVault.keychainKey() }) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    nonisolated public static var standardFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "MiNavegador/Passwords.vault")
    }

    /// Lee el archivo si aún no se ha leído.
    public func load() throws {
        guard !isLoaded else { return }
        if let data = try? Data(contentsOf: fileURL) {
            let box = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(box, using: try keyProvider())
            credentials = try JSONDecoder().decode([Credential].self, from: plain)
        }
        isLoaded = true
    }

    /// Contraseñas que sirven en una página: primero las de su mismo origen, después las del
    /// mismo sitio; dentro de cada grupo, por usuario.
    public func credentials(for page: URL) -> [Credential] {
        try? load()
        return credentials
            .compactMap { credential in credential.match(for: page).map { (credential, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.username < $1.0.username }
            .map(\.0)
    }

    /// Añade contraseñas. Si ya había una para el mismo sitio y usuario, se actualiza.
    /// Devuelve cuántas eran nuevas o cambiaron.
    @discardableResult
    public func add(_ newCredentials: [Credential]) throws -> Int {
        try load()
        var changed = 0
        for credential in newCredentials {
            if let index = credentials.firstIndex(where: { $0.host == credential.host && $0.username == credential.username }) {
                if credentials[index].password != credential.password {
                    credentials[index].password = credential.password
                    // La más reciente es la que se usa primero (inicio de sesión HTTP).
                    credentials[index].created = Date()
                    changed += 1
                }
            } else {
                credentials.append(credential)
                changed += 1
            }
        }
        if changed > 0 { try save() }
        return changed
    }

    public func remove(_ credential: Credential) throws {
        try load()
        credentials.removeAll { $0.id == credential.id }
        try save()
    }

    private func save() throws {
        let plain = try JSONEncoder().encode(credentials)
        guard let sealed = try AES.GCM.seal(plain, using: try keyProvider()).combined else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Llavero

    nonisolated private static let keychainService = "Sunset Browser Safe Storage"
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?
    nonisolated private static let keyLock = NSLock()

    /// La clave del archivo, guardada en el Llavero. Se crea la primera vez.
    nonisolated public static func keychainKey() throws -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "Sunset",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else { throw VaultError.keychain(status) }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "Sunset",
            kSecAttrLabel as String: keychainService,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychain(addStatus) }
        cachedKey = key
        return key
    }

    public enum VaultError: Error {
        case keychain(OSStatus)
    }
}
