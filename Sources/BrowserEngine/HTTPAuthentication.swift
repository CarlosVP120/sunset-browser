import AppKit
import WebKit

/// Sitios que piden usuario y contraseña por HTTP (Basic, Digest o NTLM): Supabase Studio detrás
/// de Kong, routers, servidores de pruebas… Como Safari y Chrome, se pregunta en una hoja sobre la
/// ventana. Con una sola cuenta guardada para ese origen se entra sin preguntar; al cancelar se
/// muestra la página de error del servidor.
extension WebKitPage {
    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        let methods = [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM]
        guard methods.contains(space.authenticationMethod), let site = Self.url(of: space) else {
            return (.performDefaultHandling, nil)
        }
        let saved = passwords?.credentials(for: site) ?? []
        if challenge.previousFailureCount == 0, saved.count == 1, let account = saved.first {
            return (.useCredential, URLCredential(user: account.username, password: account.password, persistence: .forSession))
        }
        guard let window = webView.window,
              let answer = await HTTPAuthenticationPrompt.ask(in: window, space: space,
                                                             failed: challenge.previousFailureCount > 0,
                                                             suggestion: saved.first)
        else { return (.rejectProtectionSpace, nil) }
        // Se guarda cuando el servidor la acepte (ver `savePendingAuthentication`).
        pendingAuthentication = answer.save ? Credential(url: site, username: answer.username, password: answer.password) : nil
        return (.useCredential, URLCredential(user: answer.username, password: answer.password, persistence: .forSession))
    }

    /// Tras iniciar sesión: si la respuesta del mismo origen ya no es 401, la contraseña era buena.
    func savePendingAuthentication(after response: URLResponse) {
        guard let pending = pendingAuthentication, let http = response as? HTTPURLResponse,
              let url = http.url, pending.match(for: url) == .sameOrigin else { return }
        pendingAuthentication = nil
        if http.statusCode != 401 { try? passwords?.add([pending]) }
    }

    /// El origen (esquema, dominio y puerto) que pide la contraseña.
    static func url(of space: URLProtectionSpace) -> URL? {
        var components = URLComponents()
        components.scheme = space.protocol ?? "https"
        components.host = space.host
        let defaultPort = components.scheme == "https" ? 443 : 80
        components.port = space.port == defaultPort || space.port == 0 ? nil : space.port
        return components.url
    }
}

/// La hoja de "Iniciar sesión" con usuario, contraseña y la opción de guardarla.
@MainActor
enum HTTPAuthenticationPrompt {
    struct Answer {
        var username: String
        var password: String
        var save: Bool
    }

    static func ask(in window: NSWindow, space: URLProtectionSpace, failed: Bool, suggestion: Credential?) async -> Answer? {
        let alert = NSAlert()
        alert.messageText = "Inicia sesión en \(space.host)"
        var details: [String] = []
        if failed { details.append("El usuario o la contraseña no son correctos.") }
        if let realm = space.realm, !realm.isEmpty { details.append("El sitio dice: «\(realm)».") }
        details.append(space.receivesCredentialSecurely
            ? "Tu usuario y contraseña viajan cifrados."
            : "Esta conexión no es segura: la contraseña se enviará sin cifrar.")
        alert.informativeText = details.joined(separator: "\n")
        alert.addButton(withTitle: "Iniciar sesión")
        // NSAlert solo le da Esc a un botón llamado "Cancel": aquí hay que ponérselo.
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"

        let username = NSTextField(string: suggestion?.username ?? "")
        username.placeholderString = "Usuario"
        let password = NSSecureTextField(string: failed ? "" : suggestion?.password ?? "")
        password.placeholderString = "Contraseña"
        let save = NSButton(checkboxWithTitle: "Guardar en las contraseñas de Sunset", target: nil, action: nil)
        save.state = .on
        for field in [username, password] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        let stack = NSStackView(views: [username, password, save])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = username.stringValue.isEmpty ? username : password

        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
        return Answer(username: username.stringValue, password: password.stringValue, save: save.state == .on)
    }
}
