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
    /// Se incrementa para pedir a la interfaz que enfoque el campo de URL.
    public private(set) var urlFocusRequests = 0

    public var showsSidebar = true
    public var showsToolbar: Bool {
        didSet { defaults.set(showsToolbar, forKey: "showsToolbar") }
    }
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
        importFromArc: Bool = true,
        defaults: UserDefaults = .standard,
        startsBackgroundWork: Bool = true
    ) {
        self.engine = engine
        self.store = store
        self.defaults = defaults
        showsToolbar = defaults.object(forKey: "showsToolbar") as? Bool ?? true
        activeSpaceID = UUID()

        if let snapshot = store?.load() ?? (importFromArc ? try? ArcImporter.load() : nil) {
            apply(snapshot)
        }
        if spaces.isEmpty {
            spaces = [
                Space(name: "Personal", icon: "house", color: .slate),
                Space(name: "Trabajo", icon: "briefcase", color: .plum),
            ]
        }
        if !spaces.contains(where: { $0.id == activeSpaceID }) {
            activeSpaceID = spaces[0].id
        }
        // Al arrancar solo se carga la pestaña visible; las demás esperan a que las abras.
        selectedTab?.wake()

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
        scheduleSave()
        return tab
    }

    /// Abre una pestaña nueva y pide enfocar el campo de URL (Cmd+T).
    public func newTab() {
        openTab()
        requestURLFocus()
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
            if let url = tab.url {
                archive.insert(ArchivedTab(id: tab.id, url: url, title: tab.displayTitle, closedAt: Date()), at: 0)
                archive = Array(archive.prefix(Self.archiveLimit))
            }
        }

        if space.selectedTabID == tab.id {
            // Pasa a la pestaña que quedó en el mismo sitio de la lista.
            let next = space.tabs.isEmpty ? nil : space.tabs[min(index, space.tabs.count - 1)]
            space.selectedTabID = next?.id
            next?.wake()
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
        selectedTab?.wake()
        scheduleSave()
    }

    public func addSpace(name: String) {
        let color = SpaceColor.palette[spaces.count % SpaceColor.palette.count]
        let space = Space(name: name, icon: "circle.grid.2x2", color: color)
        spaces.append(space)
        activate(space)
    }

    public func requestURLFocus() {
        urlFocusRequests += 1
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
        for tab in allTabs where tab.id != visibleID && !tab.isHibernated && shouldHibernate(tab) {
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
        let tab = BrowserTab(id: id, url: url, title: title, faviconURL: faviconURL) { [engine] in engine.makePage() }
        tab.onStateChange = { [weak self] in self?.scheduleSave() }
        return tab
    }

    /// Saca la pestaña de donde esté (favoritos o cualquier espacio).
    private func detach(_ tab: BrowserTab) {
        favorites.removeAll { $0.id == tab.id }
        for space in spaces { space.remove(tab) }
    }

    func snapshot() -> SidebarSnapshot {
        func record(_ tab: BrowserTab) -> SidebarSnapshot.TabRecord {
            .init(id: tab.id, url: tab.url, title: tab.title, faviconURL: tab.faviconURL)
        }
        return SidebarSnapshot(
            favorites: favorites.map(record),
            spaces: spaces.map { space in
                .init(
                    id: space.id,
                    name: space.name,
                    icon: space.icon,
                    color: space.color,
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
            archive: archive
        )
    }

    private func apply(_ snapshot: SidebarSnapshot) {
        func tab(_ record: SidebarSnapshot.TabRecord) -> BrowserTab {
            makeTab(url: record.url, id: record.id, title: record.title, faviconURL: record.faviconURL)
        }
        favorites = snapshot.favorites.map(tab)
        spaces = snapshot.spaces.map { record in
            let space = Space(id: record.id, name: record.name, icon: record.icon, color: record.color)
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
            return space
        }
        if let activeSpaceID = snapshot.activeSpaceID { self.activeSpaceID = activeSpaceID }
        archive = snapshot.archive
    }
}
