import WebKit

/// Motor provisional basado en WebKit, para poder avanzar con la interfaz
/// mientras integramos Chromium (CEF).
@MainActor
public final class WebKitEngine: WebEngine {
    private let configuration: WKWebViewConfiguration

    public init() {
        configuration = WKWebViewConfiguration()
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

    var onChange: (@MainActor (WebPageSnapshot) -> Void)?
    var view: NSView { webView }

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        // WKWebView publica estos cambios por KVO en el hilo principal.
        let notify: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.notifyChange() }
        }
        observations = [
            webView.observe(\.title) { _, _ in notify() },
            webView.observe(\.url) { _, _ in notify() },
            webView.observe(\.isLoading) { _, _ in notify() },
            webView.observe(\.canGoBack) { _, _ in notify() },
            webView.observe(\.canGoForward) { _, _ in notify() },
        ]
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    private func notifyChange() {
        onChange?(WebPageSnapshot(
            title: webView.title ?? "",
            url: webView.url,
            isLoading: webView.isLoading,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        ))
    }
}
