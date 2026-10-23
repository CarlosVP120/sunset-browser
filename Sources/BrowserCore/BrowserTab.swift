import Foundation
import Observation
import BrowserEngine

@MainActor
@Observable
public final class BrowserTab: Identifiable {
    public let id: UUID
    public private(set) var title: String
    /// Nombre puesto a mano (Renombrar pestaña); manda sobre el título de la página.
    public internal(set) var customTitle: String?
    public private(set) var url: URL?
    public private(set) var faviconURL: URL?
    public private(set) var isLoading = false
    /// Progreso de la carga, de 0 a 1.
    public private(set) var progress: Double = 1
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    /// La página en memoria; `nil` mientras la pestaña está hibernada.
    public private(set) var page: WebPage?
    public private(set) var lastActiveAt = Date()

    @ObservationIgnored private let makePage: @MainActor () -> WebPage
    @ObservationIgnored private var savedInteractionState: Any?
    /// Avisa al navegador de que hay algo nuevo que guardar.
    @ObservationIgnored var onStateChange: (() -> Void)?
    /// Zoom guardado para cada dominio.
    @ObservationIgnored var zoomForHost: ((String) -> Double)?
    /// Peticiones de la página o de una extensión, que resuelve el navegador.
    @ObservationIgnored var onRequestActivate: (() -> Void)?
    @ObservationIgnored var onRequestClose: (() -> Void)?
    @ObservationIgnored var onRequestNewTab: ((URL) -> Void)?

    init(
        id: UUID = UUID(),
        url: URL?,
        title: String = "",
        faviconURL: URL? = nil,
        makePage: @escaping @MainActor () -> WebPage
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconURL = faviconURL
        self.makePage = makePage
    }

    public var isHibernated: Bool { page == nil }

    /// Texto a mostrar en la barra lateral.
    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !title.isEmpty { return title }
        return url?.host() ?? "Nueva pestaña"
    }

    /// Crea la página si la pestaña estaba hibernada y la marca como activa.
    @discardableResult
    public func wake() -> WebPage {
        lastActiveAt = Date()
        if let page { return page }

        let page = makePage()
        page.onChange = { [weak self] snapshot in self?.apply(snapshot) }
        page.onRequestActivate = { [weak self] in self?.onRequestActivate?() }
        page.onRequestClose = { [weak self] in self?.onRequestClose?() }
        page.onRequestNewTab = { [weak self] url in self?.onRequestNewTab?(url) }
        if let host = url?.host(), let zoom = zoomForHost?(host) { page.zoom = zoom }
        if let savedInteractionState {
            page.restore(interactionState: savedInteractionState)
        } else if let url {
            page.load(url)
        }
        self.page = page
        return page
    }

    /// Libera la página de memoria conservando la URL, el título y el historial.
    public func hibernate() {
        guard let page else { return }
        savedInteractionState = page.interactionState
        page.stopLoading()
        page.willClose()
        page.onChange = nil
        self.page = nil
        isLoading = false
    }

    /// Descarta la página por completo (sin guardar historial): al volver, se carga de cero.
    /// Se usa al cambiar de perfil, para que la página use las cookies del nuevo.
    func discardPage() {
        hibernate()
        savedInteractionState = nil
    }

    public func load(_ url: URL) {
        if page == nil {
            self.url = url
            savedInteractionState = nil
        }
        wake().load(url)
    }

    public func goBack() { page?.goBack() }
    public func goForward() { page?.goForward() }

    public func reload() {
        if let page { page.reload() } else { wake() }
    }

    public func stopLoading() { page?.stopLoading() }

    /// Recarga forzada, sin caché (⇧⌘R).
    public func reloadIgnoringCache() {
        if let page { page.reloadIgnoringCache() } else { wake() }
    }

    private func apply(_ snapshot: WebPageSnapshot) {
        let before = (title, url, faviconURL)
        if !snapshot.title.isEmpty { title = snapshot.title }
        if let newHost = snapshot.url?.host(), newHost != url?.host(), let zoom = zoomForHost?(newHost) {
            page?.zoom = zoom
        }
        url = snapshot.url ?? url
        faviconURL = snapshot.faviconURL ?? faviconURL
        isLoading = snapshot.isLoading
        progress = snapshot.progress
        canGoBack = snapshot.canGoBack
        canGoForward = snapshot.canGoForward
        if before != (title, url, faviconURL) { onStateChange?() }
    }
}
