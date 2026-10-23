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
    /// Audio/vídeo principal de la página, si hay. No incluye el tiempo de reproducción
    /// (va en `mediaPosition`): así, lo que solo necesita saber si suena algo no se redibuja cada segundo.
    public private(set) var media: MediaState?
    /// Segundo actual y duración del medio. Cambia cada segundo mientras suena: solo debe leerlo
    /// la barra de progreso.
    public private(set) var mediaPosition: MediaPosition?
    /// La página en memoria; `nil` mientras la pestaña está hibernada.
    public private(set) var page: WebPage?
    public internal(set) var lastActiveAt = Date()
    /// La dirección "de casa" de una pestaña fijada o favorita (como en Arc): puedes navegar
    /// desde ella, pero al cerrarla vuelve aquí. `nil` en las pestañas normales.
    public internal(set) var pinnedURL: URL?

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
    /// Avisa de cambios de medios: (antes, ahora).
    @ObservationIgnored var onMediaUpdate: ((MediaState?, MediaState?) -> Void)?

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

    /// Es fijada o favorita y se ha movido de su dirección (la barra lateral muestra "/").
    public var isAwayFromPinned: Bool {
        guard let pinnedURL, let url else { return false }
        return !Self.isSameLocation(url, pinnedURL)
    }

    /// Misma página, sin contar "www.", la barra final ni el ancla (#…): abrir un correo en
    /// Gmail o saltar a una sección no cuenta como irse.
    static func isSameLocation(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> String {
            var host = url.host()?.lowercased() ?? ""
            if host.hasPrefix("www.") { host.removeFirst(4) }
            var path = url.path()
            while path.hasSuffix("/") { path.removeLast() }
            return "\(host)\(path)?\(url.query() ?? "")"
        }
        return key(a) == key(b)
    }

    /// Mismo sitio (dominio sin "www."), para decidir si escribir otra dirección abre pestaña nueva.
    static func isSameSite(_ a: URL, _ b: URL) -> Bool {
        func site(_ url: URL) -> String {
            let host = url.host()?.lowercased() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return site(a) == site(b)
    }

    /// Vuelve a la dirección fijada y libera la página (lo que hace Arc al cerrar una fijada).
    func resetToPinned() {
        guard let pinnedURL else { return hibernate() }
        let wasAway = isAwayFromPinned
        hibernate()
        if wasAway {
            url = pinnedURL
            savedInteractionState = nil
            canGoBack = false
            canGoForward = false
        }
    }

    /// Suena algo o está en PiP: no se hiberna (no se te corta la música).
    public var hasActiveMedia: Bool {
        media?.isPlaying == true || media?.isInPictureInPicture == true
    }

    /// Si la pestaña muestra la página Inicio.
    public var isHome: Bool { HomePage.isHome(url) }

    /// Texto a mostrar en la barra lateral.
    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if isHome { return "Inicio" }
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
        page.onMediaChange = { [weak self] state in self?.updateMedia(state) }
        if let host = url?.host(), let zoom = zoomForHost?(host) { page.zoom = zoom }
        if let savedInteractionState {
            page.restore(interactionState: savedInteractionState)
        } else if let url, !HomePage.isHome(url) {
            // Inicio no es una web: se dibuja aparte y la página queda en blanco hasta que navegues.
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
        page.onMediaChange = nil
        self.page = nil
        isLoading = false
        updateMedia(nil)
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

    func updateMedia(_ state: MediaState?) {
        let position = state.map { MediaPosition(currentTime: $0.currentTime, duration: $0.duration) }
        if position != mediaPosition { mediaPosition = position }

        var withoutTime = state
        withoutTime?.currentTime = 0
        withoutTime?.duration = 0
        let old = media
        guard old != withoutTime else { return }
        media = withoutTime
        onMediaUpdate?(old, withoutTime)
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
