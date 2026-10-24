import WebKit

/// Autorrelleno de contraseñas en las páginas.
///
/// El script vive en un "mundo" aislado (`WKContentWorld.defaultClient`): la página no puede
/// llamar a sus funciones ni hablar con Sunset. Al enfocar un campo de usuario o contraseña
/// pregunta qué cuentas hay para ese sitio (solo los nombres) y muestra una lista bajo el campo;
/// la contraseña se pide únicamente cuando el usuario hace clic de verdad en una cuenta.
/// Sunset responde según el origen real del marco, nunca según lo que diga la página.
@MainActor
final class PasswordAutofill: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "sunsetPasswords"
    private let vault: PasswordVault

    init(vault: PasswordVault) {
        self.vault = vault
    }

    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.source, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: false, in: .defaultClient))
        controller.addScriptMessageHandler(self, contentWorld: .defaultClient, name: Self.handlerName)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        // Solo sitios seguros (o desarrollo local).
        let isLocal = ["localhost", "127.0.0.1"].contains(origin.host) || origin.host.hasSuffix(".localhost")
        guard origin.protocol == "https" || (origin.protocol == "http" && isLocal), !origin.host.isEmpty,
              let body = message.body as? [String: Any], let type = body["type"] as? String
        else { return replyHandler(nil, nil) }

        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        components.port = origin.port == 0 ? nil : origin.port
        guard let page = components.url else { return replyHandler(nil, nil) }
        var accounts = vault.credentials(for: page)
        #if DEBUG
        // Solo para probar en desarrollo: una cuenta de ejemplo en localhost.
        if isLocal, ProcessInfo.processInfo.environment["SUNSET_AUTOFILL_DEMO"] == "1" {
            accounts.append(Credential(url: URL(string: "http://localhost")!, username: "demo@sunset.test", password: "contraseña-de-prueba"))
        }
        #endif
        switch type {
        case "accounts":
            replyHandler(accounts.map(\.username), nil)
        case "fill":
            let username = body["username"] as? String
            replyHandler(accounts.first { $0.username == username }?.password, nil)
        default:
            replyHandler(nil, nil)
        }
    }

    static let source = #"""
    (() => {
      if (window.__sunsetPasswords) return;
      window.__sunsetPasswords = true;
      const handler = window.webkit?.messageHandlers?.sunsetPasswords;
      if (!handler) return;

      const isPassword = el => el instanceof HTMLInputElement && el.type === 'password';
      const isUsername = el => el instanceof HTMLInputElement &&
        ['text', 'email', 'tel', ''].includes(el.type) &&
        (/user|email|login|correo|usuario|account|identifier/i.test(`${el.name} ${el.id} ${el.autocomplete} ${el.placeholder}`) ||
         el.autocomplete === 'username');
      const scopeOf = el => el.form || document;
      const passwordIn = scope => [...scope.querySelectorAll('input[type=password]')].find(visible);
      const usernameIn = (scope, password) => {
        const inputs = [...scope.querySelectorAll('input')].filter(visible);
        const before = password ? inputs.slice(0, inputs.indexOf(password)) : inputs;
        return before.reverse().find(isUsername) || before.find(i => ['text', 'email'].includes(i.type));
      };
      function visible(el) { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; }

      // Lista de cuentas, en un shadow DOM cerrado para que el CSS de la página no la toque.
      let host = null, root = null, current = null, filling = false;
      function hide() { host?.remove(); host = null; current = null; }
      function show(field, usernames) {
        hide();
        current = field;
        host = document.createElement('sunset-passwords');
        root = host.attachShadow({ mode: 'closed' });
        const dark = matchMedia('(prefers-color-scheme: dark)').matches;
        root.innerHTML = `
          <style>
            .panel { position: fixed; z-index: 2147483647; min-width: 240px; padding: 6px; border-radius: 12px;
              font: 13px -apple-system, system-ui, sans-serif; color: ${dark ? '#f5f5f7' : '#1d1d1f'};
              background: ${dark ? 'rgba(40,40,44,0.92)' : 'rgba(255,255,255,0.94)'};
              -webkit-backdrop-filter: blur(20px) saturate(1.6);
              box-shadow: 0 10px 30px rgba(0,0,0,0.22), 0 0 0 0.5px rgba(0,0,0,0.18);
              animation: in .14s ease-out; }
            @keyframes in { from { opacity: 0; transform: translateY(-4px); } }
            .title { font-size: 11px; font-weight: 600; opacity: .55; padding: 4px 8px 6px; }
            button { all: unset; box-sizing: border-box; display: flex; gap: 10px; align-items: center;
              width: 100%; padding: 7px 8px; border-radius: 8px; cursor: default; }
            button:hover, button:focus { background: ${dark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)'}; }
            .key { width: 22px; height: 22px; border-radius: 6px; display: grid; place-items: center;
              background: linear-gradient(135deg, #ff8040, #fa4d73); color: white; font-size: 12px; }
            .user { font-weight: 500; }
            .dots { opacity: .45; font-size: 11px; letter-spacing: 1px; }
          </style>
          <div class="panel"><div class="title">Contraseñas de Sunset</div></div>`;
        const panel = root.querySelector('.panel');
        for (const username of usernames) {
          const button = document.createElement('button');
          button.innerHTML = `<span class="key">🔑</span><span><div class="user"></div><div class="dots">••••••••</div></span>`;
          button.querySelector('.user').textContent = username || '(sin usuario)';
          // Al pulsar (no al soltar): el campo no pierde el foco y la lista no se cierra antes.
          // Solo cuenta un clic real del usuario (isTrusted), nunca uno simulado por la página.
          button.addEventListener('mousedown', e => {
            e.preventDefault();
            if (e.isTrusted && e.button === 0) fill(field, username);
          });
          panel.appendChild(button);
        }
        const rect = field.getBoundingClientRect();
        panel.style.left = `${Math.max(8, rect.left)}px`;
        panel.style.top = `${rect.bottom + 6}px`;
        panel.style.minWidth = `${Math.max(240, rect.width)}px`;
        document.documentElement.appendChild(host);
      }

      function setValue(input, value) {
        if (!input) return;
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        input.focus();
        setter.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }

      async function fill(field, username) {
        hide();
        filling = true;
        try {
          const password = await handler.postMessage({ type: 'fill', username });
          if (password == null) return;
          const scope = scopeOf(field);
          const passwordField = isPassword(field) ? field : passwordIn(scope);
          const usernameField = isPassword(field) ? usernameIn(scope, field) : field;
          if (usernameField && username) setValue(usernameField, username);
          if (passwordField) setValue(passwordField, password);
        } finally {
          // Que los focus de setValue no vuelvan a abrir la lista.
          setTimeout(() => { filling = false; }, 300);
        }
      }

      document.addEventListener('focusin', async e => {
        const field = e.target;
        if (!(isPassword(field) || (isUsername(field) && passwordIn(scopeOf(field))) || (isUsername(field) && field.autocomplete === 'username'))) return;
        if (field === current || filling) return;
        const usernames = await handler.postMessage({ type: 'accounts' });
        if (Array.isArray(usernames) && usernames.length && document.activeElement === field) show(field, usernames);
      }, true);
      document.addEventListener('focusout', () => setTimeout(() => {
        if (current && document.activeElement !== current) hide();
      }, 150), true);
      document.addEventListener('keydown', e => { if (e.key === 'Escape') hide(); }, true);
      addEventListener('scroll', hide, true);
      addEventListener('resize', hide);
    })();
    """#
}
