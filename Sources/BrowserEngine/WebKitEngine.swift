import WebKit

/// Motor basado en WebKit: el de Safari, que viene con macOS y comparte memoria con el sistema.
@MainActor
public final class WebKitEngine: WebEngine {
    private let configuration: WKWebViewConfiguration

    public init() {
        configuration = WKWebViewConfiguration()
        // Un solo almacén para todas las pestañas; WebKit comparte los procesos entre ellas.
        configuration.websiteDataStore = .default()
    }

    public func makePage() -> WebPage {
        WebKitPage(configuration: configuration)
    }
}

@MainActor
final class WebKitPage: WebPage {
    private let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var faviconURL: URL?

    var onChange: (@MainActor (WebPageSnapshot) -> Void)?
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

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

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
            webView.observe(\.isLoading) { webView, _ in
                notify()
                if !webView.isLoading { finished() }
            },
        ]
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func restore(interactionState: Any) { webView.interactionState = interactionState }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

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
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        ))
    }
}
