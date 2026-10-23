import AppKit

/// Estado visible de una página, sin importar qué motor la renderiza.
public struct WebPageSnapshot: Equatable, Sendable {
    public var title: String
    public var url: URL?
    public var faviconURL: URL?
    public var isLoading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool

    public init(
        title: String,
        url: URL?,
        faviconURL: URL? = nil,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.isLoading = isLoading
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
