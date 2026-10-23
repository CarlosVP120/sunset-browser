import AppKit
import BrowserEngine

/// Acciones del navegador que se pueden lanzar escribiendo en el Command Bar.
/// Son las del Command Bar de Arc que tienen sentido aquí; se encuentran también
/// por su nombre en inglés (p. ej. "clear" muestra las de borrar y limpiar).
public enum BrowserCommand: String, CaseIterable, Sendable {
    // Página
    case copyURL, copyURLAsMarkdown, reload, forceReload, findInPage, printPage
    case capturePage, viewSource, pauseAllMedia
    case zoomIn, zoomOut, resetZoom
    // Borrar y limpiar
    case clearSiteCookiesAndRefresh, clearSiteCacheAndRefresh
    case clearCache, clearCookies, clearHistory, clearBrowsingData
    case clearTodayTabs, clearUnselectedTodayTabs
    // Pestañas
    case closeTab, duplicateTab, renameTab, togglePin, addToFavorites, moveToToday
    case archiveTabsBelow, archiveTabsAbove, archiveOtherTabs, reopenClosedTab
    // Carpetas y espacios
    case newFolder, collapseAllFolders, expandAllFolders, togglePinnedSection
    case newSpace, renameSpace, editTheme, manageSpaces
    // Ventana
    case goHome
    case toggleSidebar, toggleToolbar, showLibrary, showDownloads, showShortcuts, importFromArc

    public var title: String {
        switch self {
        case .copyURL: "Copiar URL"
        case .copyURLAsMarkdown: "Copiar URL como Markdown"
        case .reload: "Recargar página"
        case .forceReload: "Recarga forzada"
        case .findInPage: "Buscar en la página"
        case .printPage: "Imprimir…"
        case .capturePage: "Capturar página"
        case .viewSource: "Ver código fuente"
        case .pauseAllMedia: "Pausar todo el audio y vídeo"
        case .zoomIn: "Acercar"
        case .zoomOut: "Alejar"
        case .resetZoom: "Tamaño real"
        case .clearSiteCookiesAndRefresh: "Borrar cookies de este sitio y recargar"
        case .clearSiteCacheAndRefresh: "Borrar caché de este sitio y recargar"
        case .clearCache: "Borrar caché"
        case .clearCookies: "Borrar cookies y datos de sitios"
        case .clearHistory: "Borrar historial"
        case .clearBrowsingData: "Borrar todos los datos de navegación…"
        case .clearTodayTabs: "Limpiar pestañas de Hoy"
        case .clearUnselectedTodayTabs: "Limpiar pestañas de Hoy no seleccionadas"
        case .closeTab: "Cerrar pestaña"
        case .duplicateTab: "Duplicar pestaña"
        case .renameTab: "Renombrar pestaña"
        case .togglePin: "Fijar o desfijar pestaña"
        case .addToFavorites: "Añadir a favoritos"
        case .moveToToday: "Mover pestaña a Hoy"
        case .archiveTabsBelow: "Archivar pestañas de abajo"
        case .archiveTabsAbove: "Archivar pestañas de arriba"
        case .archiveOtherTabs: "Archivar las demás pestañas"
        case .reopenClosedTab: "Reabrir pestaña cerrada"
        case .newFolder: "Nueva carpeta"
        case .collapseAllFolders: "Cerrar todas las carpetas"
        case .expandAllFolders: "Abrir todas las carpetas"
        case .togglePinnedSection: "Plegar o desplegar fijadas"
        case .newSpace: "Nuevo espacio"
        case .renameSpace: "Renombrar espacio"
        case .editTheme: "Editar color del tema"
        case .manageSpaces: "Gestionar espacios"
        case .toggleSidebar: "Mostrar u ocultar barra lateral"
        case .toggleToolbar: "Mostrar u ocultar barra de herramientas"
        case .goHome: "Ir a Inicio"
        case .showLibrary: "Abrir la Librería"
        case .showDownloads: "Ver descargas"
        case .showShortcuts: "Atajos de teclado"
        case .importFromArc: "Volver a importar desde Arc"
        }
    }

    public var symbol: String {
        switch self {
        case .copyURL: "link"
        case .copyURLAsMarkdown: "text.badge.plus"
        case .reload: "arrow.clockwise"
        case .forceReload: "arrow.clockwise.circle"
        case .findInPage: "text.magnifyingglass"
        case .printPage: "printer"
        case .capturePage: "camera.viewfinder"
        case .viewSource: "chevron.left.forwardslash.chevron.right"
        case .pauseAllMedia: "speaker.slash"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .resetZoom: "1.magnifyingglass"
        case .clearSiteCookiesAndRefresh: "birthday.cake"
        case .clearSiteCacheAndRefresh: "arrow.triangle.2.circlepath"
        case .clearCache: "externaldrive.badge.xmark"
        case .clearCookies: "birthday.cake"
        case .clearHistory: "clock.arrow.circlepath"
        case .clearBrowsingData: "trash"
        case .clearTodayTabs, .clearUnselectedTodayTabs: "sparkles"
        case .closeTab: "xmark"
        case .duplicateTab: "plus.square.on.square"
        case .renameTab: "pencil"
        case .togglePin: "pin"
        case .addToFavorites: "star"
        case .moveToToday: "tray.and.arrow.down"
        case .archiveTabsBelow: "arrow.down.to.line"
        case .archiveTabsAbove: "arrow.up.to.line"
        case .archiveOtherTabs: "archivebox"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .newFolder: "folder.badge.plus"
        case .collapseAllFolders: "folder"
        case .expandAllFolders: "folder.fill"
        case .togglePinnedSection: "chevron.down"
        case .newSpace: "square.stack"
        case .renameSpace: "character.cursor.ibeam"
        case .editTheme: "paintpalette"
        case .manageSpaces: "square.stack.3d.up"
        case .toggleSidebar: "sidebar.left"
        case .toggleToolbar: "menubar.rectangle"
        case .goHome: "house"
        case .showLibrary: "books.vertical"
        case .showDownloads: "arrow.down.circle"
        case .showShortcuts: "keyboard"
        case .importFromArc: "square.and.arrow.down"
        }
    }

    /// Atajo, para mostrarlo en la fila.
    public var shortcut: String? {
        switch self {
        case .copyURL: "⇧⌘C"
        case .copyURLAsMarkdown: "⌥⇧⌘C"
        case .reload: "⌘R"
        case .forceReload: "⇧⌘R"
        case .findInPage: "⌘F"
        case .printPage: "⌘P"
        case .zoomIn: "⌘+"
        case .zoomOut: "⌘-"
        case .resetZoom: "⌘0"
        case .closeTab: "⌘W"
        case .togglePin: "⌘D"
        case .reopenClosedTab: "⇧⌘T"
        case .newFolder: "⌥⌘N"
        case .toggleSidebar: "⌘S"
        case .toggleToolbar: "⌥⌘T"
        case .goHome: "⇧⌘H"
        case .showLibrary: "⇧⌘L"
        case .showDownloads: "⌥⌘L"
        default: nil
        }
    }

    /// Palabras extra (incluidos los nombres de Arc en inglés) con las que se encuentra.
    var keywords: String {
        switch self {
        case .copyURL: "copy link current url enlace"
        case .copyURLAsMarkdown: "copy url as markdown enlace"
        case .reload: "refresh reload actualizar"
        case .forceReload: "force refresh hard reload recargar sin cache"
        case .findInPage: "find search page"
        case .printPage: "print"
        case .capturePage: "capture screenshot captura pantalla"
        case .viewSource: "view source html codigo developer"
        case .pauseAllMedia: "mute all tabs silenciar pausar audio video"
        case .zoomIn: "zoom in mas grande"
        case .zoomOut: "zoom out mas pequeño"
        case .resetZoom: "zoom reset actual size 100"
        case .clearSiteCookiesAndRefresh: "clear cookies and refresh limpiar borrar sitio"
        case .clearSiteCacheAndRefresh: "clear cache and refresh limpiar borrar sitio"
        case .clearCache: "clear cache limpiar"
        case .clearCookies: "clear cookies site data limpiar"
        case .clearHistory: "clear history limpiar"
        case .clearBrowsingData: "clear browsing data limpiar todo"
        case .clearTodayTabs: "clear today tabs limpiar archivar"
        case .clearUnselectedTodayTabs: "clear unselected today tabs limpiar archivar"
        case .closeTab: "close tab"
        case .duplicateTab: "duplicate tab copia"
        case .renameTab: "rename tab nombre"
        case .togglePin: "pin unpin tab fijar"
        case .addToFavorites: "favorite star"
        case .moveToToday: "move today unpin"
        case .archiveTabsBelow: "archive tabs below cerrar"
        case .archiveTabsAbove: "archive tabs above cerrar"
        case .archiveOtherTabs: "archive other tabs cerrar demas"
        case .reopenClosedTab: "reopen undo restaurar"
        case .newFolder: "new folder crear"
        case .collapseAllFolders: "collapse close hide all folders plegar"
        case .expandAllFolders: "expand open show all folders desplegar"
        case .togglePinnedSection: "collapse pinned plegar fijadas"
        case .newSpace: "new space crear"
        case .renameSpace: "rename space"
        case .editTheme: "edit theme color space"
        case .manageSpaces: "manage spaces"
        case .toggleSidebar: "toggle show hide sidebar ocultar"
        case .toggleToolbar: "toggle toolbar url bar"
        case .goHome: "home inicio start new tab"
        case .showLibrary: "library libreria media archived tabs"
        case .showDownloads: "downloads descargas archivos"
        case .showShortcuts: "keyboard shortcuts atajos teclas"
        case .importFromArc: "arc import"
        }
    }

    /// Si tiene sentido ahora (p. ej. las de la página necesitan una pestaña abierta).
    @MainActor
    func isAvailable(in browser: Browser) -> Bool {
        let tab = browser.selectedTab
        switch self {
        case .copyURL, .copyURLAsMarkdown, .reload, .forceReload, .findInPage, .printPage, .capturePage,
             .viewSource, .pauseAllMedia, .zoomIn, .zoomOut, .resetZoom,
             .clearSiteCookiesAndRefresh, .clearSiteCacheAndRefresh, .closeTab, .duplicateTab, .renameTab,
             .togglePin, .addToFavorites:
            return tab?.url != nil && tab?.isHome == false
        case .moveToToday:
            return tab.map { browser.activeSpace.isPinned($0) || browser.isFavorite($0) } ?? false
        case .archiveTabsBelow, .archiveTabsAbove, .archiveOtherTabs, .clearTodayTabs, .clearUnselectedTodayTabs:
            return !browser.activeSpace.tabs.isEmpty
        case .reopenClosedTab:
            return !browser.archive.isEmpty
        case .collapseAllFolders, .expandAllFolders:
            return !browser.activeSpace.folders.isEmpty
        default:
            return true
        }
    }
}

extension Browser {
    public func perform(_ command: BrowserCommand) {
        let tab = selectedTab
        let space = activeSpace
        switch command {
        case .copyURL:
            guard let url = tab?.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            showToast("Enlace copiado", symbol: "link")
        case .copyURLAsMarkdown:
            copyURLAsMarkdown()
            showToast("Enlace copiado como Markdown", symbol: "text.badge.plus")
        case .reload: tab?.reload()
        case .forceReload: tab?.reloadIgnoringCache()
        case .findInPage: showFindBar()
        case .printPage: tab?.page?.printPage()
        case .capturePage: capturePage()
        case .viewSource: viewSource()
        case .pauseAllMedia:
            for tab in allTabs { tab.page?.pauseAllMedia() }
            showToast("Audio y vídeo en pausa", symbol: "speaker.slash")
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .resetZoom: resetZoom()

        case .clearSiteCookiesAndRefresh:
            clearSiteData(.cookiesAndSiteData, message: "Cookies del sitio borradas")
        case .clearSiteCacheAndRefresh:
            clearSiteData(.cache, message: "Caché del sitio borrada")
        case .clearCache:
            Task {
                await clearBrowsingData(.cache)
                showToast("Caché borrada", symbol: "checkmark.circle")
            }
        case .clearCookies:
            Task {
                await clearBrowsingData(.cookiesAndSiteData)
                showToast("Cookies y datos de sitios borrados", symbol: "checkmark.circle")
            }
        case .clearHistory:
            history.clear()
            showToast("Historial borrado", symbol: "checkmark.circle")
        case .clearBrowsingData:
            guard confirm("¿Borrar todos los datos de navegación?",
                          "Se borrarán el historial, la caché, las cookies y los datos de todos los sitios, "
                              + "en todos los perfiles. Tendrás que volver a iniciar sesión en las webs.",
                          button: "Borrar todo") else { return }
            history.clear()
            Task {
                await clearBrowsingData(.all)
                showToast("Datos de navegación borrados", symbol: "checkmark.circle")
            }
        case .clearTodayTabs:
            archiveTodayTabs(keepingSelected: false)
        case .clearUnselectedTodayTabs:
            archiveTodayTabs(keepingSelected: true)

        case .closeTab: closeSelectedTab()
        case .duplicateTab:
            guard let tab, let url = tab.url else { return }
            let copy = openTab(url)
            if let index = space.tabs.firstIndex(where: { $0.id == tab.id }) {
                move(copy, to: .today(index + 2))
            }
        case .renameTab: renamingTabID = tab?.id
        case .togglePin: if let tab { togglePin(tab) }
        case .addToFavorites: if let tab { addToFavorites(tab) }
        case .moveToToday: if let tab { move(tab, to: .today(0)) }
        case .archiveTabsBelow: archiveTodayTabs(relativeTo: tab, below: true)
        case .archiveTabsAbove: archiveTodayTabs(relativeTo: tab, below: false)
        case .archiveOtherTabs: archiveTodayTabs(keepingSelected: true)
        case .reopenClosedTab: reopenLastClosedTab()

        case .newFolder: newFolder()
        case .collapseAllFolders: setAllFolders(expanded: false)
        case .expandAllFolders: setAllFolders(expanded: true)
        case .togglePinnedSection: togglePinnedSection(space)
        case .newSpace: addSpace(name: "Espacio \(spaces.count + 1)")
        case .renameSpace: spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: .rename)
        case .editTheme: spaceEditor = SpaceEditorRequest(spaceID: space.id, kind: .theme)
        case .manageSpaces: showsSpaceManager = true

        case .toggleSidebar: showsSidebar.toggle()
        case .toggleToolbar: showsToolbar.toggle()
        case .goHome: openHome()
        case .showLibrary:
            showsSidebar = true
            showsLibrary = true
        case .showDownloads:
            librarySection = .downloads
            showsSidebar = true
            showsLibrary = true
        case .showShortcuts: showsShortcuts = true
        case .importFromArc: try? reimportFromArc()
        }
    }

    // MARK: - Pestañas de Hoy

    /// "Clear" de Arc: archiva las pestañas de Hoy (opcionalmente, todas menos la seleccionada).
    public func archiveTodayTabs(keepingSelected: Bool) {
        let space = activeSpace
        let keep = keepingSelected ? selectedTab?.id : nil
        let toArchive = space.tabs.filter { $0.id != keep }
        guard !toArchive.isEmpty else { return }
        for tab in toArchive { close(tab) }
        showToast(toArchive.count == 1 ? "1 pestaña archivada" : "\(toArchive.count) pestañas archivadas",
                  symbol: "archivebox")
    }

    private func archiveTodayTabs(relativeTo tab: BrowserTab?, below: Bool) {
        let tabs = activeSpace.tabs
        guard let tab, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let toArchive = below ? Array(tabs[(index + 1)...]) : Array(tabs[..<index])
        for tab in toArchive { close(tab) }
        if !toArchive.isEmpty {
            showToast("\(toArchive.count) pestañas archivadas", symbol: "archivebox")
        }
    }

    // MARK: - Carpetas y fijadas

    public func togglePinnedSection(_ space: Space) {
        space.isPinnedCollapsed.toggle()
        scheduleSave()
    }

    public func setAllFolders(expanded: Bool) {
        for folder in activeSpace.folders { folder.isExpanded = expanded }
        scheduleSave()
    }

    public func rename(_ tab: BrowserTab, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
        renamingTabID = nil
        scheduleSave()
    }

    // MARK: - Página

    private func clearSiteData(_ kinds: BrowsingData, message: String) {
        guard let tab = selectedTab, let host = tab.url?.host() else { return }
        Task {
            await clearBrowsingData(kinds, host: host)
            tab.reloadIgnoringCache()
            showToast(message, symbol: "checkmark.circle")
        }
    }

    /// Copia la captura al portapapeles y la guarda en el Escritorio.
    private func capturePage() {
        guard let page = selectedTab?.page else { return }
        Task {
            guard let image = await page.snapshot(),
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            try? png.write(to: desktop.appending(path: "Captura MiNavegador \(formatter.string(from: Date())).png"))
            showToast("Captura copiada y guardada en el Escritorio", symbol: "camera.viewfinder")
        }
    }

    private func viewSource() {
        guard let page = selectedTab?.page, let title = selectedTab?.displayTitle else { return }
        Task {
            guard let html = await page.pageSource(),
                  let url = URL(string: "data:text/plain;charset=utf-8;base64,\(Data(html.utf8).base64EncodedString())")
            else { return }
            let tab = openTab(url)
            tab.customTitle = "Código fuente: \(title)"
        }
    }

    private func confirm(_ title: String, _ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}
