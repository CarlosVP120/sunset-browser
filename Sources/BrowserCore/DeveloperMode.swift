import Foundation
import BrowserEngine

/// Modo desarrollador (como en Arc): en sitios que estás programando, la barra cambia de aspecto
/// y aparecen herramientas (consola, inspector, vista móvil…).
public enum DeveloperMode {
    /// Sitios en desarrollo: localhost, *.localhost, *.test, *.local, IPs de la red local.
    /// Arc solo reconoce localhost y 127.0.0.1; aquí también los demás habituales.
    public static func isLocalDevelopment(_ url: URL?) -> Bool {
        guard let url, url.scheme == "http" || url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if ["localhost", "127.0.0.1", "0.0.0.0", "::1"].contains(bare) { return true }
        if [".localhost", ".test", ".local", ".internal"].contains(where: { bare.hasSuffix($0) }) { return true }
        // IPv4 privadas: 10.x, 192.168.x, 172.16–31.x y 127.x.
        let parts = bare.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, bare.split(separator: ".").count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// "localhost:3005", lo que se ve bajo el título de la pestaña.
    public static func hostAndPort(_ url: URL?) -> String {
        guard let url, let host = url.host() else { return "" }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// Clave del sitio para recordar si el usuario activó o desactivó el modo a mano.
    static func siteKey(_ url: URL?) -> String? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

/// Mensajes de consola guardados por pestaña (los últimos 500).
public struct ConsoleLog: Equatable, Sendable {
    public private(set) var messages: [ConsoleMessage] = []
    /// Errores desde la última vez que se abrió la consola (para el globo rojo del botón).
    public private(set) var unseenErrors = 0

    static let limit = 500

    mutating func append(_ message: ConsoleMessage, isVisible: Bool) {
        messages.append(message)
        if messages.count > Self.limit { messages.removeFirst(messages.count - Self.limit) }
        if message.level == .error, !isVisible { unseenErrors += 1 }
    }

    mutating func markSeen() { unseenErrors = 0 }

    mutating func clear() {
        messages.removeAll()
        unseenErrors = 0
    }
}
