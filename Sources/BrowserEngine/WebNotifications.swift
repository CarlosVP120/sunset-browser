import AppKit
import UserNotifications
import WebKit

/// Notificaciones de las páginas como notificaciones de macOS (ver `NotificationScript`).
///
/// Cada sitio (origen: esquema, servidor y puerto) se permite o se bloquea una vez y se recuerda.
/// Sunset decide siempre por el origen real del documento, nunca por lo que diga la página.
/// Solo funcionan mientras la pestaña está abierta: sin push, con la pestaña cerrada no llegan.
@MainActor
final class WebNotifications: NSObject, WKScriptMessageHandlerWithReply, UNUserNotificationCenterDelegate {
    private let defaults: UserDefaults
    private static let defaultsKey = "notificationSites"
    /// Origen ("https://mail.example.com") → si se permiten sus notificaciones.
    private var sites: [String: Bool]
    /// Las páginas abiertas, para saber cuál envía cada mensaje y avisarles de los cambios.
    var pages: () -> [WebKitPage] = { [] }

    /// Notificaciones mostradas → la página que la envió, para traerla al hacer clic.
    private var shown: [String: WeakPage] = [:]
    private struct WeakPage { weak var page: WebKitPage? }
    /// Las peticiones de permiso en curso, una por origen (la hoja se pregunta una sola vez).
    private var prompts: [String: Task<Bool?, Never>] = [:]
    private var askedMacOS = false

    /// El centro de notificaciones de macOS. Solo existe dentro de una app (no en los tests).
    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sites = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Bool] ?? [:]
        super.init()
        _ = center
    }

    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: NotificationScript.source, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .page))
        controller.addScriptMessageHandler(self, contentWorld: .page, name: NotificationScript.handlerName)
    }

    // MARK: Permisos

    static func origin(_ origin: WKSecurityOrigin) -> String? {
        let isLocal = ["localhost", "127.0.0.1"].contains(origin.host) || origin.host.hasSuffix(".localhost")
        // Como en Chrome, solo en sitios seguros (o desarrollo local).
        guard origin.protocol == "https" || (origin.protocol == "http" && isLocal), !origin.host.isEmpty else { return nil }
        return "\(origin.protocol)://\(origin.host)" + (origin.port == 0 ? "" : ":\(origin.port)")
    }

    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        let isLocal = ["localhost", "127.0.0.1"].contains(host) || host.hasSuffix(".localhost")
        guard scheme == "https" || (scheme == "http" && isLocal) else { return nil }
        return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }

    func permission(for url: URL) -> Bool? {
        Self.origin(url).flatMap { sites[$0] }
    }

    /// Lo que ve la página en `Notification.permission`.
    func permissionValue(for origin: WKSecurityOrigin) -> String {
        switch Self.origin(origin).flatMap({ sites[$0] }) {
        case true?: "granted"
        case false?: "denied"
        case nil: Self.origin(origin) == nil ? "denied" : "default"
        }
    }

    /// Permite (`true`), bloquea (`false`) o vuelve a preguntar (`nil`) en un sitio.
    func setPermission(_ allowed: Bool?, for url: URL) {
        guard let origin = Self.origin(url) else { return }
        setPermission(allowed, origin: origin)
    }

    private func setPermission(_ allowed: Bool?, origin: String) {
        sites[origin] = allowed
        defaults.set(sites, forKey: Self.defaultsKey)
        if allowed == true { requestMacOSAuthorization() }
        // Las páginas del sitio que ya están abiertas se enteran sin recargar.
        let value = switch allowed { case true?: "granted"; case false?: "denied"; case nil: "default" }
        for page in pages() where page.webView.url.flatMap(Self.origin) == origin {
            page.webView.evaluateJavaScript("window.__sunsetNotifications?.setPermission('\(value)')")
        }
    }

    private func requestMacOSAuthorization() {
        guard !askedMacOS, let center else { return }
        askedMacOS = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: Mensajes de la página

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let origin = Self.origin(message.frameInfo.securityOrigin),
              let body = message.body as? [String: Any], let type = body["type"] as? String,
              let webView = message.webView, let page = pages().first(where: { $0.webView === webView })
        else { return replyHandler(nil, nil) }

        switch type {
        case "request":
            Task {
                let allowed = await requestPermission(origin: origin, page: page)
                replyHandler(allowed.map { $0 ? "granted" : "denied" } ?? "default", nil)
            }
        case "show":
            guard sites[origin] == true else { return replyHandler(nil, nil) }
            replyHandler(show(body, origin: origin, from: page), nil)
        case "close":
            if let id = body["id"] as? String, shown[id] != nil {
                shown[id] = nil
                center?.removeDeliveredNotifications(withIdentifiers: [id])
            }
            replyHandler(nil, nil)
        default:
            replyHandler(nil, nil)
        }
    }

    /// Pregunta al usuario, en una hoja sobre la pestaña. Solo si la pestaña está a la vista: una
    /// en segundo plano no puede sacarte un aviso (se queda en "default", como en Chrome).
    private func requestPermission(origin: String, page: WebKitPage) async -> Bool? {
        if let decided = sites[origin] { return decided }
        if let prompt = prompts[origin] { return await prompt.value }
        guard page.isActive, let window = page.webView.window, window.attachedSheet == nil else { return nil }

        let prompt = Task { () -> Bool? in
            let alert = NSAlert()
            let host = URL(string: origin)?.host() ?? origin
            alert.messageText = "«\(host)» quiere mostrarte notificaciones"
            alert.informativeText = "Te avisará aunque estés en otra pestaña o en otra app, mientras Sunset esté abierto. "
                + "Puedes cambiarlo cuando quieras desde el Command Bar: «Notificaciones de este sitio»."
            alert.addButton(withTitle: "Permitir")
            alert.addButton(withTitle: "Bloquear")
            // NSAlert solo le da Esc a un botón llamado "Cancel": cerrar con Esc no decide nada.
            alert.addButton(withTitle: "Ahora no").keyEquivalent = "\u{1b}"
            switch await alert.beginSheetModal(for: window) {
            case .alertFirstButtonReturn: return true
            case .alertSecondButtonReturn: return false
            default: return nil
            }
        }
        prompts[origin] = prompt
        let allowed = await prompt.value
        prompts[origin] = nil
        if let allowed { setPermission(allowed, origin: origin) }
        if allowed == true { Task { await warnIfBlockedByMacOS(in: window) } }
        return allowed
    }

    /// Si en Ajustes del Sistema están desactivadas las notificaciones de Sunset, el sitio puede
    /// tener permiso y aun así no llegaría nada: se avisa y se ofrece abrir los ajustes.
    private func warnIfBlockedByMacOS(in window: NSWindow) async {
        guard let center else { return }
        askedMacOS = true
        // La primera vez, macOS pregunta con su propio aviso y esto espera la respuesta.
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) != true,
              window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "macOS tiene desactivadas las notificaciones de Sunset"
        alert.informativeText = "Actívalas en Ajustes del Sistema › Notificaciones › Sunset para que los sitios puedan avisarte."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Ahora no").keyEquivalent = "\u{1b}"
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn,
              let settings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id="
                                 + (Bundle.main.bundleIdentifier ?? "")) else { return }
        NSWorkspace.shared.open(settings)
    }

    /// Envía la notificación a macOS y devuelve su identificador (para cerrarla o saber cuál se pulsó).
    private func show(_ body: [String: Any], origin: String, from page: WebKitPage) -> String? {
        guard let center else { return nil }
        requestMacOSAuthorization()
        let content = UNMutableNotificationContent()
        content.title = body["title"] as? String ?? ""
        content.body = body["body"] as? String ?? ""
        // Como Chrome: debajo del título, de qué sitio viene.
        content.subtitle = URL(string: origin)?.host() ?? origin
        content.threadIdentifier = origin
        if body["silent"] as? Bool != true { content.sound = .default }

        // Con la misma etiqueta (`tag`), una nueva sustituye a la anterior en lugar de sumarse.
        let tag = body["tag"] as? String ?? ""
        let id = tag.isEmpty ? UUID().uuidString : "\(origin)#\(tag)"
        shown[id] = WeakPage(page: page)
        shown = shown.filter { $0.value.page != nil }

        let icon = (body["icon"] as? String).flatMap(URL.init(string:))
        Task {
            if let icon, let attachment = await Self.attachment(for: icon, from: page) { content.attachments = [attachment] }
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
        return id
    }

    /// La imagen de la notificación, en un archivo temporal (macOS solo las acepta así).
    private static func attachment(for url: URL, from page: WebKitPage) async -> UNNotificationAttachment? {
        var data: Data?
        if url.scheme == "data" || url.scheme == "https" || url.scheme == "http" {
            // Del mismo sitio, con su sesión (iconos de webmails privados); si no, una descarga normal.
            if url.host() == page.webView.url?.host() { data = await page.fetchInPage(url) }
            if data == nil { data = try? await URLSession.shared.data(from: url).0 }
        }
        guard let data, let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "sunset-notification-\(UUID().uuidString).png")
        guard (try? png.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: file)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// También con Sunset delante, como Chrome: la pestaña que avisa puede no ser la visible.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clic en la notificación: Sunset delante, en la pestaña que la envió.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run { clicked(id) }
    }

    private func clicked(_ id: String) {
        NSApp.activate()
        guard let page = shown[id]?.page else { return }
        page.webView.window?.makeKeyAndOrderFront(nil)
        page.onRequestActivate?()
        let literal = (try? JSONSerialization.data(withJSONObject: [id], options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        page.webView.evaluateJavaScript("window.__sunsetNotifications?.click(\(literal)[0])")
    }
}
