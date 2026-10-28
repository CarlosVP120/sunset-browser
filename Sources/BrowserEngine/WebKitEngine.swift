import WebKit

/// Motor basado en WebKit: el de Safari, que viene con macOS y comparte memoria con el sistema.
@MainActor
public final class WebKitEngine: WebEngine {
    private let configuration: WKWebViewConfiguration
    /// `WebExtensionsHost` (macOS 15.4+), guardado sin tipo para poder compilar en versiones anteriores.
    private let extensionsHost: AnyObject?

    /// Descargas de todas las pestañas (la Librería las muestra).
    public let downloads = DownloadManager()
    /// Reparte los mensajes de medios de las páginas a cada pestaña.
    private let mediaRouter = MediaMessageRouter()
    /// Contraseñas guardadas (importadas de otros navegadores) y su autorrelleno en las páginas.
    public let passwords = PasswordVault()
    private let autofill: PasswordAutofill
    /// Notificaciones de las páginas (ver `WebNotifications`).
    private let notifications = WebNotifications()

    public init() {
        autofill = PasswordAutofill(vault: passwords)
        configuration = WKWebViewConfiguration()
        // Un solo almacén para todas las pestañas; WebKit comparte los procesos entre ellas.
        configuration.websiteDataStore = .default()
        // Nos presentamos como Safari: sin esto, webs como Google sirven su versión antigua y básica.
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        // Scroll a la frecuencia real de la pantalla (no a ~60 fps) y rueda del ratón animada.
        WebKitFeatures.applySmoothScrolling(to: configuration.preferences)
        // Seguimiento de audio y vídeo de cada página (PiP automático y reproductor lateral).
        configuration.userContentController.addUserScript(
            WKUserScript(source: MediaScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(mediaRouter, name: MediaScript.handlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: FaviconScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(mediaRouter, name: FaviconScript.handlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: ConsoleScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        configuration.userContentController.add(mediaRouter, name: ConsoleScript.handlerName)
        configuration.userContentController.add(mediaRouter, name: PDFEmbedScript.handlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: SiteQuirks.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: PDFEmbedScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        autofill.install(in: configuration.userContentController)
        notifications.install(in: configuration.userContentController)
        WebNotifications.enable(on: configuration.preferences)
        notifications.attach(to: configuration.websiteDataStore)

        if #available(macOS 15.4, *) {
            let host = WebExtensionsHost()
            // Las extensiones solo actúan en las páginas creadas con su controlador.
            configuration.webExtensionController = host.controller
            extensionsHost = host
        } else {
            extensionsHost = nil
        }
        notifications.pages = { [weak self] in self?.pages.allObjects ?? [] }
        notifications.dataStore = { [weak self] profile in
            self?.configuration(for: profile).websiteDataStore ?? .default()
        }
        notifications.openTab = { [weak self] url in self?.openTabForServiceWorker?(url) as? WebKitPage }
    }

    /// Abre una pestaña para un service worker (`clients.openWindow`, p. ej. al pulsar una
    /// notificación de Web Push) y devuelve su página.
    public var openTabForServiceWorker: ((URL) -> WebPage?)?

    /// "Version/27.0 Safari/605.1.15", con la versión de Safari instalada en el Mac.
    static var safariUserAgentSuffix: String {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
            ?? NSDictionary(contentsOfFile: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/Info.plist")
        let version = info?["CFBundleShortVersionString"] as? String ?? "27.0"
        return "Version/\(version) Safari/605.1.15"
    }

    @available(macOS 15.4, *)
    public var extensions: WebExtensionsHost {
        extensionsHost as! WebExtensionsHost
    }

    /// Configuración de cada perfil: cada uno con su propio almacén de datos web.
    private var profileConfigurations: [UUID: WKWebViewConfiguration] = [:]

    public func makePage(profile: UUID?) -> WebPage {
        makePage(profile: profile, for: nil)
    }

    public func makePage(profile: UUID?, for url: URL?) -> WebPage {
        // WebKit solo sirve las páginas de una extensión en una vista creada con su configuración.
        var extensionConfiguration: WKWebViewConfiguration?
        if #available(macOS 15.4, *), let url { extensionConfiguration = extensions.webViewConfiguration(for: url) }
        return register(WebKitPage(configuration: extensionConfiguration ?? configuration(for: profile),
                                   extensionsHost: extensionsHost, downloads: downloads, passwords: passwords,
                                   notifications: notifications))
    }

    private func register(_ page: WebKitPage) -> WebKitPage {
        mediaRouter.register(page)
        pages.add(page)
        // Las emergentes usan la configuración que da WebKit, la de la página que las abre.
        page.makePopup = { [weak self] configuration in
            guard let self else { return nil }
            return register(WebKitPage(configuration: configuration, extensionsHost: extensionsHost, downloads: downloads,
                                       passwords: passwords, notifications: notifications))
        }
        return page
    }

    /// Las páginas abiertas (sin retenerlas), para `fetchWithPageSession`.
    private let pages = NSHashTable<WebKitPage>.weakObjects()

    /// Descarga un recurso desde una página abierta del mismo origen, con su sesión (cookies y
    /// contraseña HTTP). Para iconos de sitios protegidos, que fuera de la página dan 401.
    public func fetchWithPageSession(_ url: URL) async -> Data? {
        let page = pages.allObjects.first { page in
            guard let pageURL = page.webView.url else { return false }
            return pageURL.scheme == url.scheme && pageURL.host() == url.host() && pageURL.port == url.port
        }
        return await page?.fetchInPage(url)
    }

    private func configuration(for profile: UUID?) -> WKWebViewConfiguration {
        guard let profile else { return configuration }
        if let existing = profileConfigurations[profile] { return existing }
        let profileConfiguration = configuration.copy() as! WKWebViewConfiguration
        profileConfiguration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        WebKitFeatures.applySmoothScrolling(to: profileConfiguration.preferences)
        WebNotifications.enable(on: profileConfiguration.preferences)
        notifications.attach(to: profileConfiguration.websiteDataStore)
        if profileConfiguration.userContentController !== configuration.userContentController {
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: MediaScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            profileConfiguration.userContentController.add(mediaRouter, name: MediaScript.handlerName)
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: FaviconScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            profileConfiguration.userContentController.add(mediaRouter, name: FaviconScript.handlerName)
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: ConsoleScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            profileConfiguration.userContentController.add(mediaRouter, name: ConsoleScript.handlerName)
            profileConfiguration.userContentController.add(mediaRouter, name: PDFEmbedScript.handlerName)
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: SiteQuirks.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: PDFEmbedScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            autofill.install(in: profileConfiguration.userContentController)
            notifications.install(in: profileConfiguration.userContentController)
        }
        profileConfigurations[profile] = profileConfiguration
        return profileConfiguration
    }

    public func notificationPermission(for url: URL) -> Bool? {
        notifications.permission(for: url)
    }

    public func setNotificationPermission(_ allowed: Bool?, for url: URL) {
        notifications.setPermission(allowed, for: url)
    }

    public func importCookies(_ cookies: [HTTPCookie], profile: UUID?) async {
        let store = configuration(for: profile).websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }

    public func clearBrowsingData(_ kinds: BrowsingData, host: String?) async {
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        var types = Set<String>()
        if kinds.contains(.cache) { types.formUnion(cacheTypes) }
        if kinds.contains(.cookiesAndSiteData) {
            types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes))
        }
        guard !types.isEmpty else { return }

        let stores = [configuration.websiteDataStore] + profileConfigurations.values.map(\.websiteDataStore)
        for store in stores {
            if let host {
                // Los registros van por dominio ("google.com"); vale también para sus subdominios.
                let records = await store.dataRecords(ofTypes: types).filter { record in
                    host == record.displayName || host.hasSuffix("." + record.displayName)
                }
                await store.removeData(ofTypes: types, for: records)
            } else {
                await store.removeData(ofTypes: types, modifiedSince: .distantPast)
            }
        }
    }

    /// Borra cookies, caché y almacenamiento de un perfil eliminado.
    public func removeProfileData(_ profile: UUID) {
        profileConfigurations[profile] = nil
        WKWebsiteDataStore.remove(forIdentifier: profile) { _ in }
    }
}

@MainActor
final class WebKitPage: NSObject, WebPage, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var faviconURL: URL?
    private(set) var isActive = false
    /// `WebExtensionsHost`, sin tipo por la disponibilidad (macOS 15.4+).
    let extensionsHost: AnyObject?

    var onChange: (@MainActor (WebPageSnapshot) -> Void)?
    var onRequestActivate: (@MainActor () -> Void)?
    var onRequestClose: (@MainActor () -> Void)?
    var onRequestNewTab: (@MainActor (URL) -> Void)?
    var onRequestPopup: (@MainActor (WebPage) -> Void)?
    /// Crea la página de una ventana emergente con la configuración que pide WebKit.
    var makePopup: (@MainActor (WKWebViewConfiguration) -> WebKitPage?)?
    var view: NSView { webView }
    var interactionState: Any? { webView.interactionState }

    var zoom: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }

    private static let faviconScript = "window.__sunsetFavicon ? window.__sunsetFavicon() : null"

    private weak var downloads: DownloadManager?
    /// Para los sitios que piden contraseña por HTTP (ver `HTTPAuthentication.swift`).
    private(set) weak var passwords: PasswordVault?
    private weak var notifications: WebNotifications?
    /// La contraseña recién escrita, hasta saber si el servidor la acepta.
    var pendingAuthentication: Credential?
    /// Visores nativos de PDF encima de marcos de la página (ver `PDFOverlay.swift`).
    var pdfOverlays: [Int: NSView] = [:]
    /// Autenticación HTTP por origen (esquema, servidor y puerto): la respuesta en uso, la hoja
    /// abierta (las peticiones a la vez esperan la misma), cuándo se canceló y los fallos seguidos.
    var authAnswers: [String: URLCredential] = [:]
    var authPrompts: [String: Task<HTTPAuthenticationPrompt.Answer?, Never>] = [:]
    var authCancelledAt: [String: Date] = [:]
    var authFailures: [String: Int] = [:]

    init(configuration: WKWebViewConfiguration, extensionsHost: AnyObject?, downloads: DownloadManager?,
         passwords: PasswordVault?, notifications: WebNotifications?) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.extensionsHost = extensionsHost
        self.downloads = downloads
        self.passwords = passwords
        self.notifications = notifications
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // "Inspeccionar elemento" en el menú contextual (herramientas para desarrolladores).
        webView.isInspectable = true
        webView.uiDelegate = self
        webView.navigationDelegate = self

        // WKWebView publica estos cambios por KVO en el hilo principal.
        let notify: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.notifyChange() }
        }
        let finished: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.pageDidFinishLoading() }
        }
        observations = [
            webView.observe(\.title) { _, _ in notify() },
            webView.observe(\.url) { _, _ in notify() },
            webView.observe(\.canGoBack) { _, _ in notify() },
            webView.observe(\.canGoForward) { _, _ in notify() },
            webView.observe(\.estimatedProgress) { _, _ in notify() },
            webView.observe(\.isLoading) { webView, _ in
                notify()
                if !webView.isLoading { finished() }
            },
        ]

        if #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didOpen(self) }
    }

    func load(_ url: URL) {
        if url.isFileURL {
            // Archivos locales: WebKit necesita permiso de lectura sobre su carpeta.
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }
    func restore(interactionState: Any) { webView.interactionState = interactionState }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadIgnoringCache() { webView.reloadFromOrigin() }
    func stopLoading() { webView.stopLoading() }

    func find(_ text: String, backwards: Bool) async -> Bool {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return (try? await webView.find(text, configuration: configuration).matchFound) ?? false
    }

    func snapshot() async -> NSImage? {
        try? await webView.takeSnapshot(configuration: nil)
    }

    func pageSource() async -> String? {
        try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
    }

    func pauseAllMedia() {
        webView.pauseAllMediaPlayback()
    }

    func isEditingText() async -> Bool {
        // Un iframe con el foco (p. ej. el editor de Google Docs) cuenta como escribir: desde aquí
        // no se ve su interior y es mejor no quitarle el ⌘Z.
        let script = """
        (() => {
          const el = document.activeElement;
          if (!el || el === document.body) return document.designMode === 'on';
          return el.isContentEditable || el.tagName === 'IFRAME' || el.tagName === 'TEXTAREA' ||
            (el.tagName === 'INPUT' && !['button', 'checkbox', 'radio', 'submit', 'reset', 'range', 'color', 'file', 'image'].includes(el.type));
        })()
        """
        return (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    // MARK: Audio y vídeo

    var onMediaChange: (@MainActor (MediaState?) -> Void)?

    func setPictureInPicture(_ enabled: Bool) {
        webView.evaluateJavaScript("window.__miNavegadorMedia?.setPictureInPicture(\(enabled))")
    }

    func mediaCommand(_ command: MediaCommand) {
        let call = switch command {
        case .togglePlayback: "togglePlayback()"
        case .pause: "pause()"
        case .toggleMute: "toggleMute()"
        case .seek(let seconds): "seek(\(seconds))"
        case .seekTo(let seconds): "seekTo(\(seconds))"
        }
        webView.evaluateJavaScript("window.__miNavegadorMedia?.\(call)")
    }

    func receiveMediaMessage(_ body: Any) {
        guard let state = body as? [String: Any] else {
            onMediaChange?(nil)
            return
        }
        onMediaChange?(MediaState(
            isPlaying: state["playing"] as? Bool ?? false,
            isMuted: state["muted"] as? Bool ?? false,
            hasVideo: state["video"] as? Bool ?? false,
            isInPictureInPicture: state["pip"] as? Bool ?? false,
            currentTime: (state["time"] as? NSNumber)?.doubleValue ?? 0,
            duration: (state["duration"] as? NSNumber)?.doubleValue ?? 0
        ))
    }

    /// `fetch` dentro de la página (mismo origen), devuelto en base64 para cruzar a Swift.
    func fetchInPage(_ url: URL) async -> Data? {
        let script = """
            const response = await fetch(url, { credentials: 'include' });
            if (!response.ok) return null;
            const bytes = new Uint8Array(await response.arrayBuffer());
            let binary = '';
            for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
            return btoa(binary);
            """
        let result = try? await webView.callAsyncJavaScript(script, arguments: ["url": url.absoluteString],
                                                             in: nil, contentWorld: .defaultClient)
        return (result as? String).flatMap { Data(base64Encoded: $0) }
    }

    func printPage() {
        guard let window = webView.window else { return }
        let operation = webView.printOperation(with: .shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else { return }
        self.isActive = isActive
        if isActive, #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didActivate(self) }
    }

    func willClose() {
        if #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didClose(self) }
    }

    // MARK: WKNavigationDelegate (descargas)

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Enlaces con el atributo `download`.
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        savePendingAuthentication(after: navigationResponse.response)
        // Lo que no se puede mostrar (zip, dmg…) o lo que el servidor marca como adjunto, se descarga.
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            // Un `blob:` que la página pone en un marco no es una descarga que hayas pedido (p. ej. un
            // PDF sin tipo en una vista previa; ver PDFEmbedScript): no se guarda en Descargas.
            if !navigationResponse.isForMainFrame, navigationResponse.response.url?.scheme == "blob" {
                return .cancel
            }
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads?.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads?.track(download)
    }

    // MARK: WKUIDelegate

    /// Enlaces con `target="_blank"` y `window.open`: se abren en una pestaña nueva. Su vista se crea
    /// aquí con la configuración de WebKit para que siga unida a la página (`window.opener`): así
    /// el inicio de sesión con Google le devuelve el resultado a la página y se cierra solo.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let onRequestPopup, let popup = makePopup?(configuration) {
            onRequestPopup(popup)
            return popup.webView
        }
        if let url = navigationAction.request.url { onRequestNewTab?(url) }
        return nil
    }

    /// `<input type="file">`: el selector de archivos de macOS (p. ej. la e.firma del SAT o adjuntar en
    /// un correo), en una hoja sobre la ventana.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    /// La página se cierra sola (`window.close()`), como la ventana de Google al terminar.
    func webViewDidClose(_ webView: WKWebView) {
        onRequestClose?()
    }

    /// `prompt()` no muestra nada en Sunset; solo contesta la pregunta del permiso de notificaciones
    /// (ver `NotificationScript`), según el origen real del marco.
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard prompt == NotificationScript.permissionQuery, frame.isMainFrame else { return nil }
        return notifications?.permissionValue(for: frame.securityOrigin)
    }

    /// Un service worker pide traer su pestaña (`client.focus()`, p. ej. al pulsar su notificación).
    @objc(_focusWebViewFromServiceWorker:)
    func focusFromServiceWorker(_ webView: WKWebView) {
        NSApp.activate()
        webView.window?.makeKeyAndOrderFront(nil)
        onRequestActivate?()
    }

    // MARK: Modo desarrollador

    private var developerMode = false
    private var onConsoleMessage: (@MainActor (ConsoleMessage) -> Void)?

    func setDeveloperMode(_ enabled: Bool, onMessage: (@MainActor (ConsoleMessage) -> Void)?) {
        developerMode = enabled
        onConsoleMessage = enabled ? onMessage : nil
        enableConsoleInPage()
    }

    /// Cada documento nuevo empieza con la consola apagada: se enciende si la pestaña la usa.
    private func enableConsoleInPage() {
        webView.evaluateJavaScript("window.__sunsetConsole && window.__sunsetConsole.enable(\(developerMode))")
    }

    func receiveConsole(_ body: Any) {
        guard developerMode, let body = body as? [String: Any] else { return }
        guard let text = body["text"] as? String else { return }
        let level = (body["level"] as? String).flatMap(ConsoleMessage.Level.init(rawValue:)) ?? .log
        onConsoleMessage?(ConsoleMessage(level: level, text: text, source: body["source"] as? String))
    }

    // MARK: Inspector web

    private var inspector: NSObject? { webView.value(forKey: "_inspector") as? NSObject }

    private func call(_ selector: String, on object: NSObject?) {
        let selector = NSSelectorFromString(selector)
        if let object, object.responds(to: selector) { object.perform(selector) }
    }

    var isInspectorVisible: Bool {
        (inspector?.value(forKey: "isVisible") as? Bool) ?? false
    }

    /// El inspector web de WebKit (el de Safari), acoplado bajo la página como las DevTools de Arc.
    func showInspector(_ panel: InspectorPanel) {
        let inspector = inspector
        switch panel {
        case .console:
            call("showConsole", on: inspector)
        case .elements:
            call("show", on: inspector)
        case .pickElement:
            call("show", on: inspector)
            if (inspector?.value(forKey: "isElementSelectionActive") as? Bool) != true {
                call("toggleElementSelection", on: inspector)
            }
        case .network:
            call("show", on: inspector)
            selectNetworkTab(attempts: 20)
        }
    }

    func closeInspector() {
        call("close", on: inspector)
    }

    /// WebKit no tiene "mostrar Red": se le pide a la propia interfaz del inspector (su web)
    /// cuando termina de cargar.
    private func selectNetworkTab(attempts: Int) {
        guard attempts > 0 else { return }
        guard let frontend = inspector?.value(forKey: "inspectorWebView") as? WKWebView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.selectNetworkTab(attempts: attempts - 1) }
            return
        }
        frontend.evaluateJavaScript("typeof WI !== 'undefined' && WI.showNetworkTab ? (WI.showNetworkTab(), true) : false") { [weak self] result, _ in
            MainActor.assumeIsolated {
                if (result as? Bool) != true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.selectNetworkTab(attempts: attempts - 1) }
                }
            }
        }
    }

    private func pageDidFinishLoading() {
        if developerMode { enableConsoleInPage() }
        Task { [weak self] in
            guard let self else { return }
            let href = try? await webView.evaluateJavaScript(Self.faviconScript) as? String
            let url = href.flatMap(URL.init(string:))
            guard url != faviconURL else { return }
            faviconURL = url
            notifyChange()
        }
    }

    /// La página cambió su icono (Gmail lo hace al llegar correos: el número de no leídos).
    func receiveFavicon(_ href: String?) {
        let url = href.flatMap(URL.init(string:))
        guard let url, url != faviconURL else { return }
        faviconURL = url
        notifyChange()
    }

    private func notifyChange() {
        onChange?(WebPageSnapshot(
            title: webView.title ?? "",
            url: webView.url,
            faviconURL: faviconURL,
            isLoading: webView.isLoading,
            progress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        ))
        if #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didChange(self) }
    }
}

/// Recibe los mensajes del script de medios y los entrega a la página que los envió.
@MainActor
final class MediaMessageRouter: NSObject, WKScriptMessageHandler {
    private struct WeakPage { weak var page: WebKitPage? }
    private var pages: [ObjectIdentifier: WeakPage] = [:]

    func register(_ page: WebKitPage) {
        pages = pages.filter { $0.value.page != nil }
        pages[ObjectIdentifier(page.webView)] = WeakPage(page: page)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let page = pages[ObjectIdentifier(webView)]?.page else { return }
        if message.name == FaviconScript.handlerName {
            page.receiveFavicon(message.body as? String)
        } else if message.name == ConsoleScript.handlerName {
            page.receiveConsole(message.body)
        } else if message.name == PDFEmbedScript.handlerName {
            page.receivePDFMessage(message.body)
        } else {
            page.receiveMediaMessage(message.body)
        }
    }
}
