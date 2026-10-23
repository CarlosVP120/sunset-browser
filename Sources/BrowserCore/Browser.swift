import Foundation
import Observation
import BrowserEngine

/// Estado global del navegador: favoritos, espacios, archivo y acciones sobre pestañas.
@MainActor
@Observable
public final class Browser {
    public private(set) var favorites: [BrowserTab] = []
    public private(set) var spaces: [Space] = []
    public private(set) var activeSpaceID: Space.ID
    /// Pestañas cerradas, de la más reciente a la más antigua.
    public private(set) var archive: [ArchivedTab] = []
    /// Perfiles además del predeterminado.
    public private(set) var profiles: [Profile] = []
    /// La Librería (descargas, media, espacios, archivo) en lugar de la barra lateral.
    public var showsLibrary = false
    public var librarySection: LibrarySection = .downloads
    /// Pestaña que se está renombrando en la barra lateral.
    public var renamingTabID: BrowserTab.ID?
    /// Al cambiar de pestaña, el vídeo que suena pasa a imagen en imagen (como Arc).
    public var autoPictureInPicture: Bool {
        didSet { defaults.set(autoPictureInPicture, forKey: "autoPictureInPicture") }
    }
    /// Reproductores que el usuario quitó de la barra lateral (vuelven si suena otra vez).
    public internal(set) var dismissedMediaTabIDs: Set<BrowserTab.ID> = []
    @ObservationIgnored private var lastVisibleTabID: BrowserTab.ID?
    /// Ventana con la lista de atajos de teclado.
    public var showsShortcuts = false
    /// Aviso breve abajo ("Enlace copiado").
    public private(set) var toast: Toast?
    /// Editor abierto de un espacio (icono, nombre o tema).
    public var spaceEditor: SpaceEditorRequest?
    /// Ventana para ordenar, renombrar y borrar espacios.
    public var showsSpaceManager = false
    /// La bienvenida (o solo el importador), si hay que mostrarla.
    public var welcome: WelcomeRequest?
    /// Es la primera vez que se abre (no había barra lateral guardada).
    public private(set) var isFirstLaunch = false
    /// Barra de búsqueda en la página (⌘F).
    public var isFindBarVisible = false
    /// Se incrementa para pedir a la barra de búsqueda el siguiente (+1) o el anterior (-1).
    public internal(set) var findRequest = FindRequest(direction: 0)
    /// El Command Bar abierto, si lo hay.
    public var commandBar: CommandBarMode?
    /// Último cambio de zoom, para mostrar el indicador.
    public private(set) var zoomIndicator: ZoomIndicator?
    public let history: History

    public var showsSidebar = true
    public var showsToolbar: Bool {
        didSet { defaults.set(showsToolbar, forKey: "showsToolbar") }
    }
    /// Ancho de la barra lateral, que se cambia arrastrando su borde.
    public var sidebarWidth: Double {
        didSet { defaults.set(sidebarWidth, forKey: "sidebarWidth") }
    }
    public static let sidebarWidthRange: ClosedRange<Double> = 180...440
    /// Minutos sin usarse tras los que una pestaña se hiberna.
    public var hibernateAfter: TimeInterval = 10 * 60

    @ObservationIgnored private let engine: WebEngine
    @ObservationIgnored private let store: SidebarStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hibernationTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?

    private static let archiveLimit = 200

    public init(
        engine: WebEngine,
        store: SidebarStore? = .standard,
        historyFileURL: URL? = History.standardFileURL,
        importFromArc: Bool = true,
        defaults: UserDefaults = .standard,
        startsBackgroundWork: Bool = true
    ) {
        self.engine = engine
        self.store = store
        self.defaults = defaults
        history = History(fileURL: historyFileURL)
        showsToolbar = defaults.object(forKey: "showsToolbar") as? Bool ?? true
        sidebarWidth = defaults.object(forKey: "sidebarWidth") as? Double ?? 240
        autoPictureInPicture = defaults.object(forKey: "autoPictureInPicture") as? Bool ?? true
        activeSpaceID = UUID()

        let saved = store?.load()
        isFirstLaunch = store != nil && saved == nil
        if let snapshot = saved ?? (importFromArc ? try? ArcImporter.load() : nil) {
            apply(snapshot)
        }
        if spaces.isEmpty {
            spaces = [
                Space(name: "Personal", icon: "house", theme: .dark(from: .navy)),
                Space(name: "Trabajo", icon: "briefcase", theme: .dark(from: .plum)),
            ]
        }
        if !spaces.contains(where: { $0.id == activeSpaceID }) {
            activeSpaceID = spaces[0].id
        }
        // Al arrancar solo se carga la pestaña visible; las demás esperan a que las abras.
        showSelectedTab()

        if startsBackgroundWork {
            startHibernationTimer()
            watchMemoryPressure()
        }
    }

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    public var selectedTab: BrowserTab? {
        let space = activeSpace
        guard let id = space.selectedTabID else { return nil }
        return favorites.first { $0.id == id } ?? space.allTabs.first { $0.id == id }
    }

    /// Todas las pestañas de todos los espacios, incluidos los favoritos.
    public var allTabs: [BrowserTab] {
        favorites + spaces.flatMap(\.allTabs)
    }

    public func isFavorite(_ tab: BrowserTab) -> Bool {
        favorites.contains { $0.id == tab.id }
    }

    // MARK: - Pestañas

    @discardableResult
    public func openTab(_ url: URL? = nil, in space: Space? = nil) -> BrowserTab {
        let space = space ?? activeSpace
        let tab = makeTab(url: url)
        space.tabs.insert(tab, at: 0)
        space.selectedTabID = tab.id
        tab.wake()
        syncActivePage()
        scheduleSave()
        return tab
    }

    /// Abre el Command Bar para una pestaña nueva (⌘T). La pestaña se crea al elegir destino.
    public func newTab() {
        commandBar = .newTab
    }

    /// Abre el Command Bar sobre la pestaña actual (⌘L o clic en la dirección).
    public func editCurrentTab() {
        commandBar = selectedTab == nil ? .newTab : .currentTab
    }

    public func tab(withID id: BrowserTab.ID) -> BrowserTab? {
        allTabs.first { $0.id == id }
    }

    public func folder(withID id: Folder.ID) -> Folder? {
        spaces.lazy.flatMap(\.folders).first { $0.id == id }
    }

    /// Navega en la pestaña actual o abre una si no hay ninguna.
    public func navigate(to input: String) {
        guard let url = URLInput.resolve(input) else { return }
        if let tab = selectedTab {
            tab.load(url)
        } else {
            openTab(url)
        }
    }

    public func select(_ tab: BrowserTab) {
        activeSpace.selectedTabID = tab.id
        tab.wake()
        syncActivePage()
        scheduleSave()
    }

    /// Como en Arc: cerrar una pestaña fijada o favorita solo la descarga;
    /// cerrar una pestaña normal la manda al archivo.
    public func close(_ tab: BrowserTab) {
        let space = activeSpace
        let index = space.tabs.firstIndex { $0.id == tab.id } ?? 0
        let keepsTab = isFavorite(tab) || space.isPinned(tab)

        tab.hibernate()
        if !keepsTab {
            space.remove(tab)
            if let url = tab.url, !tab.isHome {
                archive.insert(ArchivedTab(id: tab.id, url: url, title: tab.displayTitle, closedAt: Date()), at: 0)
                archive = Array(archive.prefix(Self.archiveLimit))
            }
        }

        if space.selectedTabID == tab.id {
            // Pasa a la pestaña que quedó en el mismo sitio de la lista.
            let next = space.tabs.isEmpty ? nil : space.tabs[min(index, space.tabs.count - 1)]
            space.selectedTabID = next?.id
            next?.wake()
            syncActivePage()
        }
        scheduleSave()
    }

    public func closeSelectedTab() {
        if let tab = selectedTab { close(tab) }
    }

    public func restore(_ archived: ArchivedTab) {
        archive.removeAll { $0.id == archived.id }
        openTab(archived.url)
    }

    public func reopenLastClosedTab() {
        if let last = archive.first { restore(last) }
    }

    public func clearArchive() {
        archive.removeAll()
        scheduleSave()
    }

    public func togglePin(_ tab: BrowserTab) {
        let space = activeSpace
        if space.isPinned(tab) {
            space.remove(tab)
            space.tabs.insert(tab, at: 0)
        } else {
            detach(tab)
            space.pinned.append(.tab(tab))
        }
        scheduleSave()
    }

    public func addToFavorites(_ tab: BrowserTab) {
        guard !isFavorite(tab) else { return }
        detach(tab)
        favorites.append(tab)
        scheduleSave()
    }

    public func removeFromFavorites(_ tab: BrowserTab) {
        guard isFavorite(tab) else { return }
        favorites.removeAll { $0.id == tab.id }
        activeSpace.tabs.insert(tab, at: 0)
        scheduleSave()
    }

    // MARK: - Carpetas

    @discardableResult
    public func newFolder(named name: String = "Nueva carpeta") -> Folder {
        let folder = Folder(name: name)
        activeSpace.pinned.append(.folder(folder))
        scheduleSave()
        return folder
    }

    public func move(_ tab: BrowserTab, to folder: Folder) {
        detach(tab)
        folder.tabs.append(tab)
        folder.isExpanded = true
        scheduleSave()
    }

    public func toggle(_ folder: Folder) {
        folder.isExpanded.toggle()
        scheduleSave()
    }

    public func rename(_ folder: Folder, to name: String) {
        folder.name = name
        scheduleSave()
    }

    /// Borra la carpeta y deja sus pestañas fijadas sueltas.
    public func delete(_ folder: Folder) {
        let space = activeSpace
        guard let index = space.pinned.firstIndex(where: { $0.id == folder.id }) else { return }
        space.pinned.replaceSubrange(index...index, with: folder.tabs.map { .tab($0) })
        scheduleSave()
    }

    // MARK: - Espacios

    public func activate(_ space: Space) {
        activeSpaceID = space.id
        showSelectedTab()
        scheduleSave()
    }

    public func addSpace(name: String) {
        let color = SpaceColor.palette[spaces.count % SpaceColor.palette.count]
        let space = Space(name: name, icon: "circle.grid.2x2", theme: .dark(from: color))
        spaces.append(space)
        activate(space)
    }

    /// Sustituye la barra lateral por la de Arc (mantiene el archivo y el historial).
    public func reimportFromArc() throws {
        replaceSidebar(with: try ArcImporter.load())
    }

    /// Sustituye la barra lateral (espacios, favoritos y pestañas) por otra; se conservan el
    /// archivo y el historial.
    public func replaceSidebar(with imported: SidebarSnapshot) {
        var snapshot = imported
        snapshot.archive = archive
        for tab in allTabs { tab.hibernate() }
        apply(snapshot)
        showSelectedTab()
        scheduleSave()
    }

    /// Trae la barra lateral de otro navegador. Si Sunset aún está vacío, la sustituye; si ya
    /// tienes pestañas, añade sus espacios y favoritos a los tuyos.
    public func mergeSidebar(_ imported: SidebarSnapshot) {
        guard !favorites.isEmpty || !allTabs.isEmpty else {
            replaceSidebar(with: imported)
            return
        }
        var merged = snapshot()
        let knownHosts = Set(favorites.compactMap { $0.url?.host() })
        merged.favorites += imported.favorites.filter { !knownHosts.contains($0.url?.host() ?? "") }
        let knownSpaces = Set(merged.spaces.map(\.id))
        merged.spaces += imported.spaces.filter { !knownSpaces.contains($0.id) }
        replaceSidebar(with: merged)
    }

    /// Añade un espacio con marcadores traídos de otro navegador: los enlaces sueltos quedan
    /// fijados y cada carpeta de marcadores, como carpeta (plegada).
    @discardableResult
    public func addImportedSpace(named name: String, icon: String, color: SpaceColor,
                                 pinned: [(title: String, url: URL)],
                                 folders: [(name: String, links: [(title: String, url: URL)])]) -> Space {
        let space = Space(name: name, icon: icon, theme: .dark(from: color))
        space.pinned = pinned.map { .tab(makeTab(url: $0.url, title: $0.title)) }
            + folders.map { folder in
                .folder(Folder(name: folder.name, isExpanded: false,
                               tabs: folder.links.map { makeTab(url: $0.url, title: $0.title) }))
            }
        spaces.append(space)
        activate(space)
        return space
    }

    /// Añade sitios a favoritos (los que no estén ya).
    public func addFavorites(_ links: [(title: String, url: URL)]) {
        let existing = Set(favorites.compactMap { $0.url?.host() })
        for link in links where !existing.contains(link.url.host() ?? "") {
            favorites.append(makeTab(url: link.url, title: link.title))
        }
        scheduleSave()
    }

    /// Añade cookies traídas de otro navegador (las sesiones siguen iniciadas en Sunset).
    public func importCookies(_ cookies: [HTTPCookie]) async {
        await engine.importCookies(cookies, profile: nil)
    }

    // MARK: - Arrastrar y soltar

    /// Mueve una pestaña a otra posición: favoritos, fijadas, una carpeta o las de hoy.
    public func move(_ tab: BrowserTab, to location: DropLocation) {
        let space = activeSpace
        // Si se mueve hacia abajo dentro de la misma lista, al sacarla los índices bajan uno.
        func adjusted(_ index: Int, in ids: [UUID]) -> Int {
            guard let old = ids.firstIndex(of: tab.id), old < index else { return index }
            return index - 1
        }

        var location = location
        switch location {
        case .favorites(let index): location = .favorites(adjusted(index, in: favorites.map(\.id)))
        case .pinned(let index): location = .pinned(adjusted(index, in: space.pinned.map(\.id)))
        case .folder(let folder, let index): location = .folder(folder, adjusted(index, in: folder.tabs.map(\.id)))
        case .today(let index): location = .today(adjusted(index, in: space.tabs.map(\.id)))
        }

        detach(tab)
        switch location {
        case .favorites(let index):
            favorites.insert(tab, at: min(index, favorites.count))
        case .pinned(let index):
            space.pinned.insert(.tab(tab), at: min(index, space.pinned.count))
        case .folder(let folder, let index):
            folder.tabs.insert(tab, at: min(index, folder.tabs.count))
            folder.isExpanded = true
        case .today(let index):
            space.tabs.insert(tab, at: min(index, space.tabs.count))
        }
        scheduleSave()
    }

    /// Mueve una carpeta dentro de la sección fijada.
    public func move(_ folder: Folder, toPinnedIndex index: Int) {
        let space = activeSpace
        guard let old = space.pinned.firstIndex(where: { $0.id == folder.id }) else { return }
        let item = space.pinned.remove(at: old)
        let index = old < index ? index - 1 : index
        space.pinned.insert(item, at: min(max(index, 0), space.pinned.count))
        scheduleSave()
    }

    /// Abre una URL arrastrada desde fuera en la posición indicada.
    public func open(_ url: URL, at location: DropLocation) {
        let tab = openTab(url)
        move(tab, to: location)
    }

    // MARK: - Zoom

    private static let zoomSteps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    public func zoomIn() { stepZoom(by: 1) }
    public func zoomOut() { stepZoom(by: -1) }
    public func resetZoom() { setZoom(1) }

    private func stepZoom(by step: Int) {
        guard let current = selectedTab?.page?.zoom else { return }
        let index = Self.zoomSteps.firstIndex { $0 >= current - 0.001 } ?? Self.zoomSteps.count - 1
        let next = Self.zoomSteps[min(max(index + step, 0), Self.zoomSteps.count - 1)]
        setZoom(next)
    }

    private func setZoom(_ zoom: Double) {
        guard let tab = selectedTab, let page = tab.page else { return }
        page.zoom = zoom
        if let host = tab.url?.host() {
            var levels = defaults.dictionary(forKey: "zoomLevels") as? [String: Double] ?? [:]
            levels[host] = zoom == 1 ? nil : zoom
            defaults.set(levels, forKey: "zoomLevels")
        }
        zoomIndicator = ZoomIndicator(zoom: zoom)
    }

    private func zoom(forHost host: String) -> Double {
        (defaults.dictionary(forKey: "zoomLevels") as? [String: Double])?[host] ?? 1
    }

    // MARK: - Hibernación

    /// Hiberna las pestañas que no se han usado en `hibernateAfter` segundos.
    /// La pestaña visible nunca se hiberna.
    public func hibernateIdleTabs(now: Date = Date()) {
        hibernate(where: { now.timeIntervalSince($0.lastActiveAt) >= hibernateAfter })
    }

    /// Hiberna todo menos la pestaña visible (cuando macOS avisa de que falta memoria).
    public func hibernateBackgroundTabs() {
        hibernate(where: { _ in true })
    }

    private func hibernate(where shouldHibernate: (BrowserTab) -> Bool) {
        let visibleID = selectedTab?.id
        for tab in allTabs where tab.id != visibleID && !tab.isHibernated && !tab.hasActiveMedia && shouldHibernate(tab) {
            tab.hibernate()
        }
    }

    private func startHibernationTimer() {
        hibernationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.hibernateIdleTabs()
            }
        }
    }

    private func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.hibernateBackgroundTabs() }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Guardado

    /// Guarda la barra lateral un segundo después del último cambio.
    func scheduleSave() {
        guard store != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        saveTask?.cancel()
        try? store?.save(snapshot())
    }

    private func makeTab(url: URL?, id: UUID = UUID(), title: String = "", faviconURL: URL? = nil) -> BrowserTab {
        let tab = BrowserTab(id: id, url: url, title: title, faviconURL: faviconURL) { [weak self, engine] in
            // La página se crea con el perfil del espacio en el que está la pestaña.
            engine.makePage(profile: self?.profileID(forTabID: id))
        }
        tab.onStateChange = { [weak self, weak tab] in
            guard let self else { return }
            scheduleSave()
            if let tab, let url = tab.url { history.record(url: url, title: tab.title) }
        }
        tab.zoomForHost = { [weak self] host in self?.zoom(forHost: host) ?? 1 }
        tab.onRequestActivate = { [weak self, weak tab] in
            if let self, let tab { reveal(tab) }
        }
        tab.onRequestClose = { [weak self, weak tab] in
            if let self, let tab { close(tab) }
        }
        tab.onRequestNewTab = { [weak self] url in self?.openTab(url) }
        tab.onMediaUpdate = { [weak self, weak tab] old, new in
            if let self, let tab { mediaChanged(tab, from: old, to: new) }
        }
        return tab
    }

    func replaceSpaces(_ newSpaces: [Space]) {
        spaces = newSpaces
        scheduleSave()
    }

    func setProfiles(_ newProfiles: [Profile]) {
        profiles = newProfiles
        scheduleSave()
    }

    func removeProfileData(_ profile: UUID) {
        engine.removeProfileData(profile)
    }

    func clearBrowsingData(_ kinds: BrowsingData, host: String? = nil) async {
        await engine.clearBrowsingData(kinds, host: host)
    }

    public func showToast(_ message: String, symbol: String) {
        toast = Toast(message: message, symbol: symbol)
    }

    func insertIntoArchive(_ archived: ArchivedTab) {
        archive.insert(archived, at: 0)
        archive = Array(archive.prefix(Self.archiveLimit))
    }

    /// Una pestaña nueva (hibernada) con la misma página.
    func copyTab(_ tab: BrowserTab) -> BrowserTab {
        makeTab(url: tab.url, title: tab.title, faviconURL: tab.faviconURL)
    }

    /// Muestra la pestaña, cambiando de espacio si hace falta.
    public func reveal(_ tab: BrowserTab) {
        if !isFavorite(tab), let space = spaces.first(where: { $0.allTabs.contains { $0.id == tab.id } }),
           space.id != activeSpaceID {
            activeSpaceID = space.id
        }
        select(tab)
    }

    func showSelectedTab() {
        selectedTab?.wake()
        syncActivePage()
    }

    /// Avisa a cada página de si es la visible (lo necesitan las extensiones) y, al cambiar de
    /// pestaña, pasa a PiP el vídeo que se deja sonando y saca de PiP el de la pestaña a la que vuelves.
    private func syncActivePage() {
        let selectedID = selectedTab?.id
        for tab in allTabs {
            tab.page?.setActive(tab.id == selectedID)
        }
        guard lastVisibleTabID != selectedID else { return }
        if autoPictureInPicture, let previousID = lastVisibleTabID, let previous = tab(withID: previousID),
           let media = previous.media, media.isPlaying, media.hasVideo, !media.isInPictureInPicture {
            previous.page?.setPictureInPicture(true)
        }
        if let current = selectedTab, current.media?.isInPictureInPicture == true {
            current.page?.setPictureInPicture(false)
        }
        lastVisibleTabID = selectedID
    }

    /// Reacciona a los cambios de medios de una pestaña.
    private func mediaChanged(_ tab: BrowserTab, from old: MediaState?, to new: MediaState?) {
        if new?.isPlaying == true { dismissedMediaTabIDs.remove(tab.id) }
        // Botón "volver a la pestaña" del PiP: sale de PiP y sigue sonando.
        if old?.isInPictureInPicture == true, new?.isInPictureInPicture == false, new?.isPlaying == true,
           selectedTab?.id != tab.id {
            reveal(tab)
        }
    }

    /// Saca la pestaña de donde esté (favoritos o cualquier espacio).
    func detach(_ tab: BrowserTab) {
        favorites.removeAll { $0.id == tab.id }
        for space in spaces { space.remove(tab) }
    }

    func snapshot() -> SidebarSnapshot {
        func record(_ tab: BrowserTab) -> SidebarSnapshot.TabRecord {
            .init(id: tab.id, url: tab.url, title: tab.title, faviconURL: tab.faviconURL, customTitle: tab.customTitle)
        }
        return SidebarSnapshot(
            favorites: favorites.map(record),
            spaces: spaces.map { space in
                .init(
                    id: space.id,
                    name: space.name,
                    icon: space.icon,
                    theme: space.theme,
                    profileID: space.profileID,
                    isPinnedCollapsed: space.isPinnedCollapsed,
                    pinned: space.pinned.map { item in
                        switch item {
                        case .tab(let tab):
                            .tab(record(tab))
                        case .folder(let folder):
                            .folder(.init(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                                          tabs: folder.tabs.map(record)))
                        }
                    },
                    tabs: space.tabs.map(record),
                    selectedTabID: space.selectedTabID
                )
            },
            activeSpaceID: activeSpaceID,
            archive: archive,
            profiles: profiles
        )
    }

    private func apply(_ snapshot: SidebarSnapshot) {
        func tab(_ record: SidebarSnapshot.TabRecord) -> BrowserTab {
            let tab = makeTab(url: record.url, id: record.id, title: record.title, faviconURL: record.faviconURL)
            tab.customTitle = record.customTitle
            return tab
        }
        favorites = snapshot.favorites.map(tab)
        spaces = snapshot.spaces.map { record in
            let space = Space(id: record.id, name: record.name, icon: record.icon, theme: record.theme)
            space.pinned = record.pinned.map { item in
                switch item {
                case .tab(let tabRecord):
                    .tab(tab(tabRecord))
                case .folder(let folder):
                    .folder(Folder(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                                   tabs: folder.tabs.map(tab)))
                }
            }
            space.tabs = record.tabs.map(tab)
            space.selectedTabID = record.selectedTabID
            space.profileID = record.profileID
            space.isPinnedCollapsed = record.isPinnedCollapsed
            return space
        }
        if let activeSpaceID = snapshot.activeSpaceID { self.activeSpaceID = activeSpaceID }
        archive = snapshot.archive
        profiles = snapshot.profiles
    }
}
