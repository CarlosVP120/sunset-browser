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

    public init() {
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

        if #available(macOS 15.4, *) {
            let host = WebExtensionsHost()
            // Las extensiones solo actúan en las páginas creadas con su controlador.
            configuration.webExtensionController = host.controller
            extensionsHost = host
        } else {
            extensionsHost = nil
        }
    }

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
        let page = WebKitPage(configuration: configuration(for: profile), extensionsHost: extensionsHost, downloads: downloads)
        mediaRouter.register(page)
        return page
    }

    private func configuration(for profile: UUID?) -> WKWebViewConfiguration {
        guard let profile else { return configuration }
        if let existing = profileConfigurations[profile] { return existing }
        let profileConfiguration = configuration.copy() as! WKWebViewConfiguration
        profileConfiguration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        WebKitFeatures.applySmoothScrolling(to: profileConfiguration.preferences)
        if profileConfiguration.userContentController !== configuration.userContentController {
            profileConfiguration.userContentController.addUserScript(
                WKUserScript(source: MediaScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            profileConfiguration.userContentController.add(mediaRouter, name: MediaScript.handlerName)
        }
        profileConfigurations[profile] = profileConfiguration
        return profileConfiguration
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
    var view: NSView { webView }
    var interactionState: Any? { webView.interactionState }

    var zoom: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }

    private static let faviconScript = """
    (() => {
      const links = [...document.querySelectorAll("link[rel~='icon'], link[rel='apple-touch-icon']")];
      const best = links.find(l => (l.getAttribute('rel') || '').includes('apple-touch-icon')) || links[0];
      return best ? best.href : null;
    })()
    """

    private weak var downloads: DownloadManager?

    init(configuration: WKWebViewConfiguration, extensionsHost: AnyObject?, downloads: DownloadManager?) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.extensionsHost = extensionsHost
        self.downloads = downloads
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
        // Lo que no se puede mostrar (zip, dmg…) o lo que el servidor marca como adjunto, se descarga.
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
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

    /// Enlaces con `target="_blank"` y `window.open`: se abren en una pestaña nueva.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { onRequestNewTab?(url) }
        return nil
    }

    private func pageDidFinishLoading() {
        Task { [weak self] in
            guard let self else { return }
            let href = try? await webView.evaluateJavaScript(Self.faviconScript) as? String
            let url = href.flatMap(URL.init(string:))
            guard url != faviconURL else { return }
            faviconURL = url
            notifyChange()
        }
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
        page.receiveMediaMessage(message.body)
    }
}
