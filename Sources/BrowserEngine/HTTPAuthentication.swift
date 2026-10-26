import AppKit
import WebKit
import os

/// Sitios que piden usuario y contraseña por HTTP (Basic, Digest o NTLM): Supabase Studio detrás
/// de Kong o Envoy, routers, servidores de pruebas… Como Safari y Chrome, se pregunta en una hoja
/// sobre la ventana. Una página pide muchas cosas a la vez (HTML, JS, API) y cada petición recibe
/// su propio desafío: se agrupan para que haya una sola hoja por sitio y todas usen la respuesta.
/// Con una sola cuenta guardada para ese origen se entra sin preguntar; al cancelar se muestra la
/// página del servidor y el sitio deja de preguntar un momento.
extension WebKitPage {
    private static let authLog = Logger(subsystem: "com.carlosvp.minavegador", category: "http-auth")

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        let methods = [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM]
        guard methods.contains(space.authenticationMethod), let site = Self.url(of: space) else {
            return (.performDefaultHandling, nil)
        }
        // Por origen, no por realm: Envoy (Supabase) pone la dirección de cada petición en el realm,
        // y como Chromium, una vez dentro del sitio la contraseña sirve para todas sus rutas.
        let key = "\(space.protocol ?? "https")://\(space.host):\(space.port)"
        let tried = challenge.proposedCredential
        let status = (challenge.failureResponse as? HTTPURLResponse)?.statusCode ?? 0
        Self.authLog.notice("""
            desafío \(space.authenticationMethod, privacy: .public) en \(key, privacy: .public): \
            fallos \(challenge.previousFailureCount), respuesta \(status), \
            \(challenge.failureResponse?.url?.path() ?? "-", privacy: .public), \
            probada \(tried?.hasPassword == true ? "sí" : "no", privacy: .public)
            """)

        // Recién cancelado: no se vuelve a preguntar (las demás peticiones de la página fallan).
        if let cancelled = authCancelledAt[key], Date().timeIntervalSince(cancelled) < 10 {
            return (.rejectProtectionSpace, nil)
        }
        // Ya hay respuesta para este sitio y esta petición no la ha probado: se usa sin preguntar.
        let triedKnown = authAnswers[key].map { tried?.user == $0.user && tried?.password == $0.password } ?? false
        if let known = authAnswers[key], !(challenge.previousFailureCount > 0 && triedKnown) {
            return (.useCredential, known)
        }
        // Primer intento con la cuenta guardada más reciente de este origen (la última que funcionó),
        // como Chrome: así la sesión sigue tras reiniciar Sunset aunque haya otras guardadas.
        let saved = (passwords?.credentials(for: site) ?? [])
            .filter { $0.match(for: site) == .sameOrigin }
            .sorted { $0.created > $1.created }
        if authAnswers[key] == nil, challenge.previousFailureCount == 0, let account = saved.first {
            let credential = URLCredential(user: account.username, password: account.password, persistence: .forSession)
            authAnswers[key] = credential
            return (.useCredential, credential)
        }
        // La respuesta ya probada falló: otra vez la hoja, como mucho tres veces seguidas.
        let failed = challenge.previousFailureCount > 0 && triedKnown
        if failed { authFailures[key, default: 0] += 1 }
        if authFailures[key, default: 0] >= 3 {
            authFailures[key] = 0
            authAnswers[key] = nil
            authCancelledAt[key] = Date()
            return (.rejectProtectionSpace, nil)
        }
        guard let window = webView.window else { return (.rejectProtectionSpace, nil) }
        let prompt = authPrompts[key] ?? Task {
            await HTTPAuthenticationPrompt.ask(in: window, space: space, failed: failed, suggestion: saved.first)
        }
        authPrompts[key] = prompt
        let answer = await prompt.value
        authPrompts[key] = nil
        guard let answer else {
            authAnswers[key] = nil
            authCancelledAt[key] = Date()
            return (.rejectProtectionSpace, nil)
        }
        let credential = URLCredential(user: answer.username, password: answer.password, persistence: .forSession)
        if authAnswers[key]?.user != answer.username || authAnswers[key]?.password != answer.password {
            authAnswers[key] = credential
            // Se guarda cuando el servidor la acepte (ver `savePendingAuthentication`).
            pendingAuthentication = answer.save ? Credential(url: site, username: answer.username, password: answer.password) : nil
        }
        return (.useCredential, credential)
    }

    /// Tras iniciar sesión: si la respuesta del mismo origen ya no es 401, la contraseña era buena.
    func savePendingAuthentication(after response: URLResponse) {
        guard let pending = pendingAuthentication, let http = response as? HTTPURLResponse,
              let url = http.url, pending.match(for: url) == .sameOrigin else { return }
        pendingAuthentication = nil
        guard http.statusCode != 401 else { return }
        try? passwords?.add([pending])
        authFailures.removeAll()
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
        // Algunos servidores (Envoy) ponen ahí la dirección pedida: solo se muestra si es un nombre.
        if let realm = space.realm, !realm.isEmpty, !realm.contains("://") { details.append("El sitio dice: «\(realm)».") }
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
