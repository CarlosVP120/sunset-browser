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
    /// Recarga forzada: vuelve a descargarlo todo, sin caché.
    func reloadIgnoringCache()
    func stopLoading()
    /// Busca texto en la página y lo resalta. Devuelve si lo encontró.
    func find(_ text: String, backwards: Bool) async -> Bool
    func printPage()
    /// Captura de lo que se ve de la página.
    func snapshot() async -> NSImage?
    /// El HTML actual de la página.
    func pageSource() async -> String?
    /// Pausa audio y vídeo de la página.
    func pauseAllMedia()
    /// Si se está escribiendo en la página (un campo, un editor): ahí ⌘Z deshace lo escrito.
    func isEditingText() async -> Bool

    /// Cambios en el audio/vídeo principal de la página (`nil` si no hay ninguno).
    var onMediaChange: (@MainActor (MediaState?) -> Void)? { get set }
    /// Pone o quita el vídeo principal en imagen en imagen (PiP).
    func setPictureInPicture(_ enabled: Bool)
    func mediaCommand(_ command: MediaCommand)

    // Modo desarrollador
    /// Activa la consola de la página: `onMessage` recibe lo que escribe (y lo que tenía guardado).
    func setDeveloperMode(_ enabled: Bool, onMessage: (@MainActor (ConsoleMessage) -> Void)?)
    /// Abre las herramientas de desarrollo del motor (en WebKit, el inspector web de Safari;
    /// en Chromium serían sus DevTools) en la pestaña indicada.
    func showInspector(_ panel: InspectorPanel)
    func closeInspector()
    /// Si las herramientas están abiertas.
    var isInspectorVisible: Bool { get }
}

/// Pestaña de las herramientas de desarrollo.
public enum InspectorPanel: Sendable {
    case elements, console, network
    /// Elementos, con el selector activo para elegir uno en la página.
    case pickElement
}

public extension WebPage {
    func setDeveloperMode(_ enabled: Bool, onMessage: (@MainActor (ConsoleMessage) -> Void)?) {}
    func showInspector(_ panel: InspectorPanel) {}
    func closeInspector() {}
    var isInspectorVisible: Bool { false }
}

/// Controles del reproductor de la barra lateral.
public enum MediaCommand: Sendable {
    case togglePlayback, pause, toggleMute
    /// Avanza o retrocede unos segundos.
    case seek(Double)
    /// Salta a un segundo concreto (la barra de progreso).
    case seekTo(Double)
}

/// Fábrica de páginas. Cambiar de motor (WebKit → Chromium/CEF) es cambiar esta pieza.
@MainActor
public protocol WebEngine: AnyObject {
    /// Crea una página. `profile` separa cookies, sesiones y almacenamiento (perfiles de Arc).
    func makePage(profile: UUID?) -> WebPage
    /// Igual, sabiendo qué se va a abrir: las páginas de una extensión (`webkit-extension://`)
    /// necesitan una configuración propia de esa extensión.
    func makePage(profile: UUID?, for url: URL?) -> WebPage
    /// Borra los datos web (cookies, caché, almacenamiento) de un perfil eliminado.
    func removeProfileData(_ profile: UUID)
    /// Borra datos de navegación de todos los perfiles; con `host`, solo los de ese sitio.
    func clearBrowsingData(_ kinds: BrowsingData, host: String?) async
    /// Añade cookies (sesiones traídas de otro navegador) al almacén de un perfil.
    func importCookies(_ cookies: [HTTPCookie], profile: UUID?) async
    /// Si el sitio de `url` puede mostrar notificaciones: sí, no, o aún no se ha decidido (`nil`).
    func notificationPermission(for url: URL) -> Bool?
    /// Permite, bloquea o vuelve a preguntar (`nil`) las notificaciones del sitio de `url`.
    func setNotificationPermission(_ allowed: Bool?, for url: URL)
}

public extension WebEngine {
    func makePage(profile: UUID?, for url: URL?) -> WebPage { makePage(profile: profile) }
    func notificationPermission(for url: URL) -> Bool? { nil }
    func setNotificationPermission(_ allowed: Bool?, for url: URL) {}
}

/// Qué datos de navegación borrar.
public struct BrowsingData: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Caché de páginas, imágenes y scripts.
    public static let cache = BrowsingData(rawValue: 1 << 0)
    /// Cookies, almacenamiento local, bases de datos y service workers.
    public static let cookiesAndSiteData = BrowsingData(rawValue: 1 << 1)
    public static let all: BrowsingData = [.cache, .cookiesAndSiteData]
}
