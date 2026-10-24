import Foundation

/// Qué partes de una extensión de Chrome no existen en WebKit (ni en Safari). Se avisa al
/// instalarla y en el panel de extensiones: con ellas la extensión no funciona o funciona a medias.
public enum ExtensionCompatibility {
    /// Permisos de Chrome sin equivalente en WebKit, con una descripción para el usuario.
    static let unsupportedPermissions: [String: String] = [
        "debugger": "controlar el navegador (chrome.debugger)",
        "sidePanel": "panel lateral (chrome.sidePanel)",
        "offscreen": "documentos en segundo plano (chrome.offscreen)",
        "nativeMessaging": "hablar con apps del Mac (nativeMessaging)",
        "tabGroups": "grupos de pestañas (chrome.tabGroups)",
        "identity": "inicio de sesión de Chrome (chrome.identity)",
        "tabCapture": "capturar el audio o vídeo de una pestaña (chrome.tabCapture)",
        "desktopCapture": "capturar la pantalla (chrome.desktopCapture)",
        "pageCapture": "guardar páginas como MHTML (chrome.pageCapture)",
        "proxy": "configurar un proxy (chrome.proxy)",
        "tts": "texto a voz (chrome.tts)",
        "ttsEngine": "motor de texto a voz (chrome.ttsEngine)",
        "bookmarks": "marcadores (chrome.bookmarks)",
        "history": "historial (chrome.history)",
        "topSites": "sitios más visitados (chrome.topSites)",
        "readingList": "lista de lectura (chrome.readingList)",
        "fontSettings": "ajustes de fuentes (chrome.fontSettings)",
        "gcm": "mensajes push de Google (chrome.gcm)",
        "printerProvider": "impresoras (chrome.printerProvider)",
    ]

    /// Lo que la extensión pide y WebKit no tiene, ya descrito para el usuario. Vacío si es compatible.
    public static func unsupportedFeatures(manifest: [String: Any]) -> [String] {
        let permissions = (manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        var features = permissions.compactMap { permission -> String? in
            if let description = unsupportedPermissions[permission] { return description }
            if permission.hasPrefix("enterprise.") || permission.hasPrefix("system.") {
                return "APIs de Chrome OS (chrome.\(permission))"
            }
            return nil
        }
        // El panel lateral también se declara con su propia clave del manifiesto.
        if manifest["side_panel"] != nil, !permissions.contains("sidePanel") {
            features.append(unsupportedPermissions["sidePanel"]!)
        }
        return features
    }

    /// Lee el `manifest.json` de una extensión desempaquetada.
    public static func unsupportedFeatures(inExtensionAt folder: URL) -> [String] {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return unsupportedFeatures(manifest: manifest)
    }
}
