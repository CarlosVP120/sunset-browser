import AppKit

/// Estado visible de una página, sin importar qué motor la renderiza.
public struct WebPageSnapshot: Equatable, Sendable {
    public var title: String
    public var url: URL?
    public var faviconURL: URL?
    public var isLoading: Bool
    /// Progreso estimado de la carga, de 0 a 1.
    public var progress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool

    public init(
        title: String,
        url: URL?,
        faviconURL: URL? = nil,
        isLoading: Bool,
        progress: Double = 1,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.isLoading = isLoading
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}

/// Una página web abierta (una pestaña). Cada motor la implementa a su manera.
@MainActor
public protocol WebPage: AnyObject {
    /// La vista nativa que muestra la página.
    var view: NSView { get }
    /// Se llama cada vez que cambia el título, la URL, el icono o el estado de carga.
    var onChange: (@MainActor (WebPageSnapshot) -> Void)? { get set }
    /// Historial y posición de scroll, para poder hibernar la página y restaurarla.
    var interactionState: Any? { get }
    /// Zoom de la página (1 = 100 %).
    var zoom: Double { get set }

    /// Peticiones que llegan de fuera (p. ej. una extensión): mostrar o cerrar esta pestaña.
    var onRequestActivate: (@MainActor () -> Void)? { get set }
    var onRequestClose: (@MainActor () -> Void)? { get set }
    /// Un enlace pide abrirse en otra pestaña (`target="_blank"`, `window.open`).
    var onRequestNewTab: (@MainActor (URL) -> Void)? { get set }

    /// Si es la pestaña visible del navegador.
    func setActive(_ isActive: Bool)
    /// La página se va a descartar (hibernación o cierre).
    func willClose()

    func load(_ url: URL)
    func restore(interactionState: Any)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
}

/// Fábrica de páginas. Cambiar de motor (WebKit → Chromium/CEF) es cambiar esta pieza.
@MainActor
public protocol WebEngine: AnyObject {
    func makePage() -> WebPage
}
