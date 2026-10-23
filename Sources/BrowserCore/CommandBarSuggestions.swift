import AppKit

/// Acciones del navegador que se pueden lanzar escribiendo en el Command Bar.
public enum BrowserCommand: String, CaseIterable, Sendable {
    case copyURL, reload, closeTab, togglePin, addToFavorites
    case reopenClosedTab, newFolder, newSpace
    case toggleSidebar, toggleToolbar
    case zoomIn, zoomOut, resetZoom
    case importFromArc

    public var title: String {
        switch self {
        case .copyURL: "Copiar URL"
        case .reload: "Recargar página"
        case .closeTab: "Cerrar pestaña"
        case .togglePin: "Fijar o desfijar pestaña"
        case .addToFavorites: "Añadir a favoritos"
        case .reopenClosedTab: "Reabrir pestaña cerrada"
        case .newFolder: "Nueva carpeta"
        case .newSpace: "Nuevo espacio"
        case .toggleSidebar: "Mostrar u ocultar barra lateral"
        case .toggleToolbar: "Mostrar u ocultar barra de herramientas"
        case .zoomIn: "Acercar"
        case .zoomOut: "Alejar"
        case .resetZoom: "Tamaño real"
        case .importFromArc: "Volver a importar desde Arc"
        }
    }

    public var symbol: String {
        switch self {
        case .copyURL: "link"
        case .reload: "arrow.clockwise"
        case .closeTab: "xmark"
        case .togglePin: "pin"
        case .addToFavorites: "star"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .newFolder: "folder.badge.plus"
        case .newSpace: "square.stack"
        case .toggleSidebar: "sidebar.left"
        case .toggleToolbar: "menubar.rectangle"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .resetZoom: "1.magnifyingglass"
        case .importFromArc: "square.and.arrow.down"
        }
    }

    /// Palabras extra con las que también se encuentra el comando.
    var keywords: String {
        switch self {
        case .copyURL: "copy link enlace"
        case .reload: "refresh actualizar"
        case .closeTab: "close"
        case .togglePin: "pin"
        case .addToFavorites: "favorite star"
        case .reopenClosedTab: "undo restaurar"
        case .newFolder: "folder crear"
        case .newSpace: "space crear"
        case .toggleSidebar: "sidebar ocultar"
        case .toggleToolbar: "toolbar url bar"
        case .zoomIn: "zoom mas grande"
        case .zoomOut: "zoom menos pequeño"
        case .resetZoom: "zoom 100 restablecer"
        case .importFromArc: "arc import"
        }
    }
}

/// Una fila del Command Bar.
public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case open(URL)
        case switchToTab(UUID)
        case switchToSpace(UUID)
        case command(BrowserCommand)
    }

    public let id: String
    public let title: String
    /// Se muestra después de « — », en gris.
    public let detail: String?
    public let action: Action
    /// Página de la que mostrar el favicon.
    public let pageURL: URL?
    public let faviconURL: URL?
    /// SF Symbol cuando no hay favicon (búsquedas, comandos, espacios).
    public let symbol: String?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        action: Action,
        pageURL: URL? = nil,
        faviconURL: URL? = nil,
        symbol: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.pageURL = pageURL
        self.faviconURL = faviconURL
        self.symbol = symbol
    }
}

extension Browser {
    /// Sugerencias para lo escrito, de más a menos relevante, como el Command Bar de Arc:
    /// primero el destino directo, luego pestañas abiertas, historial, búsquedas y comandos.
    public func suggestions(for query: String, mode: CommandBarMode, searchSuggestions: [String]) -> [Suggestion] {
        let needle = query.searchNormalized
        var results: [Suggestion] = []
        var seenURLs = Set<String>()

        func add(_ suggestion: Suggestion) {
            if case .open(let url) = suggestion.action {
                guard seenURLs.insert(url.absoluteString).inserted else { return }
            }
            results.append(suggestion)
        }

        let current = mode == .currentTab ? selectedTab : nil

        // 1. Sin texto: la página actual y lo más reciente.
        if needle.isEmpty {
            for tab in recentTabs(limit: 5) where tab.id != current?.id {
                add(switchSuggestion(tab))
            }
            return results
        }

        // 2. Si lo escrito es la URL de la pestaña actual, la propia página va primero.
        if let current, let url = current.url, url.absoluteString == query {
            add(Suggestion(id: "current", title: current.displayTitle, detail: nil, action: .open(url),
                           pageURL: url, faviconURL: current.faviconURL))
        }

        // 3. El destino directo: una dirección o una búsqueda en Google.
        if let url = URLInput.resolve(query) {
            if URLInput.isSearch(url) {
                add(Suggestion(id: "search", title: query, detail: "Buscar en Google", action: .open(url),
                               symbol: "magnifyingglass"))
            } else {
                add(Suggestion(id: "direct", title: url.absoluteString, detail: "Abrir", action: .open(url),
                               pageURL: url, symbol: "globe"))
            }
        }

        // 4. Pestañas abiertas que coinciden.
        let matchingTabs = allTabs.filter { tab in
            tab.id != current?.id && (tab.title.searchNormalized.contains(needle)
                || (tab.url?.host() ?? "").searchNormalized.contains(needle))
        }
        for tab in matchingTabs.prefix(3) { add(switchSuggestion(tab)) }

        // 5. Historial.
        for entry in history.search(query, limit: 6) where !matchingTabs.contains(where: { $0.url == entry.url }) {
            add(Suggestion(
                id: "history:\(entry.url.absoluteString)",
                title: entry.title.isEmpty ? entry.url.absoluteString : entry.title,
                detail: Self.shortHost(entry.url),
                action: .open(entry.url),
                pageURL: entry.url
            ))
        }

        // 6. Espacios y comandos.
        for space in spaces where space.name.searchNormalized.contains(needle) {
            results.append(Suggestion(id: "space:\(space.id)", title: space.name, detail: "Ir al espacio",
                                      action: .switchToSpace(space.id), symbol: "square.stack"))
        }
        if needle.count >= 2 {
            let commands = BrowserCommand.allCases.filter {
                "\($0.title) \($0.keywords)".searchNormalized.contains(needle)
            }
            for command in commands.prefix(3) {
                results.append(Suggestion(id: "command:\(command.rawValue)", title: command.title,
                                          action: .command(command), symbol: command.symbol))
            }
        }

        // 7. Sugerencias de búsqueda.
        for term in searchSuggestions.prefix(4) where term.searchNormalized != needle {
            guard let url = URLInput.searchURL(for: term) else { continue }
            add(Suggestion(id: "suggest:\(term)", title: term, action: .open(url), symbol: "magnifyingglass"))
        }

        return Array(results.prefix(9))
    }

    /// Ejecuta la fila elegida.
    public func perform(_ suggestion: Suggestion, mode: CommandBarMode) {
        commandBar = nil
        switch suggestion.action {
        case .open(let url):
            if mode == .currentTab, let tab = selectedTab {
                tab.load(url)
            } else {
                openTab(url)
            }
        case .switchToTab(let id):
            if let tab = tab(withID: id) { reveal(tab) }
        case .switchToSpace(let id):
            if let space = spaces.first(where: { $0.id == id }) { activate(space) }
        case .command(let command):
            perform(command)
        }
    }

    public func perform(_ command: BrowserCommand) {
        let tab = selectedTab
        switch command {
        case .copyURL:
            guard let url = tab?.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case .reload: tab?.reload()
        case .closeTab: closeSelectedTab()
        case .togglePin: if let tab { togglePin(tab) }
        case .addToFavorites: if let tab { addToFavorites(tab) }
        case .reopenClosedTab: reopenLastClosedTab()
        case .newFolder: newFolder()
        case .newSpace: addSpace(name: "Espacio \(spaces.count + 1)")
        case .toggleSidebar: showsSidebar.toggle()
        case .toggleToolbar: showsToolbar.toggle()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .resetZoom: resetZoom()
        case .importFromArc: try? reimportFromArc()
        }
    }

    private func switchSuggestion(_ tab: BrowserTab) -> Suggestion {
        Suggestion(
            id: "tab:\(tab.id)",
            title: tab.displayTitle,
            detail: "Cambiar a la pestaña",
            action: .switchToTab(tab.id),
            pageURL: tab.url,
            faviconURL: tab.faviconURL
        )
    }

    private func recentTabs(limit: Int) -> [BrowserTab] {
        Array(allTabs.filter { !$0.isHibernated || $0.url != nil }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .prefix(limit))
    }

    static func shortHost(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let short = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(short):\(port)" }
        return short
    }
}
