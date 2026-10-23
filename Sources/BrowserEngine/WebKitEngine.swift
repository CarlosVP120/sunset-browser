import WebKit

/// Motor basado en WebKit: el de Safari, que viene con macOS y comparte memoria con el sistema.
@MainActor
public final class WebKitEngine: WebEngine {
    private let configuration: WKWebViewConfiguration
    /// `WebExtensionsHost` (macOS 15.4+), guardado sin tipo para poder compilar en versiones anteriores.
    private let extensionsHost: AnyObject?

    public init() {
        configuration = WKWebViewConfiguration()
        // Un solo almacén para todas las pestañas; WebKit comparte los procesos entre ellas.
        configuration.websiteDataStore = .default()

        if #available(macOS 15.4, *) {
            let host = WebExtensionsHost()
            // Las extensiones solo actúan en las páginas creadas con su controlador.
            configuration.webExtensionController = host.controller
            extensionsHost = host
        } else {
            extensionsHost = nil
        }
    }

    @available(macOS 15.4, *)
    public var extensions: WebExtensionsHost {
        extensionsHost as! WebExtensionsHost
    }

    public func makePage() -> WebPage {
        WebKitPage(configuration: configuration, extensionsHost: extensionsHost)
    }
}

@MainActor
final class WebKitPage: NSObject, WebPage, WKUIDelegate {
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

    init(configuration: WKWebViewConfiguration, extensionsHost: AnyObject?) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.extensionsHost = extensionsHost
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.uiDelegate = self

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

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func restore(interactionState: Any) { webView.interactionState = interactionState }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else { return }
        self.isActive = isActive
        if isActive, #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didActivate(self) }
    }

    func willClose() {
        if #available(macOS 15.4, *) { (extensionsHost as? WebExtensionsHost)?.didClose(self) }
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
