import AppKit

/// Una fila del Command Bar.
public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case open(URL)
        case switchToTab(UUID)
        case switchToSpace(UUID)
        case command(BrowserCommand)
        case moveTabToSpace(UUID)
        case openFolder(UUID)
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
    /// Atajo de teclado a mostrar a la derecha.
    public let shortcut: String?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        action: Action,
        pageURL: URL? = nil,
        faviconURL: URL? = nil,
        symbol: String? = nil,
        shortcut: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.pageURL = pageURL
        self.faviconURL = faviconURL
        self.symbol = symbol
        self.shortcut = shortcut
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

        // 4. Comandos que empiezan por lo escrito (p. ej. "clear", "limpiar", "copiar").
        let commands = matchingCommands(needle)
        for command in commands.strong.prefix(8) { results.append(commandSuggestion(command)) }

        // 5. Pestañas abiertas que coinciden.
        let matchingTabs = allTabs.filter { tab in
            tab.id != current?.id && (tab.displayTitle.searchNormalized.contains(needle)
                || (tab.url?.host() ?? "").searchNormalized.contains(needle))
        }
        for tab in matchingTabs.prefix(3) { add(switchSuggestion(tab)) }

        // 6. Historial.
        for entry in history.search(query, limit: 6) where !matchingTabs.contains(where: { $0.url == entry.url }) {
            add(Suggestion(
                id: "history:\(entry.url.absoluteString)",
                title: entry.title.isEmpty ? entry.url.absoluteString : entry.title,
                detail: Self.shortHost(entry.url),
                action: .open(entry.url),
                pageURL: entry.url
            ))
        }

        // Espacios, carpetas, mover la pestaña y el resto de comandos.
        for space in spaces where space.name.searchNormalized.contains(needle) {
            results.append(Suggestion(id: "space:\(space.id)", title: space.name, detail: "Ir al espacio",
                                      action: .switchToSpace(space.id), symbol: "square.stack"))
        }
        for folder in activeSpace.folders where folder.name.searchNormalized.contains(needle) {
            results.append(Suggestion(id: "folder:\(folder.id)", title: folder.name, detail: "Abrir carpeta",
                                      action: .openFolder(folder.id), symbol: "folder"))
        }
        if let tab = selectedTab, tab.url != nil, needle.count >= 2 {
            let wantsMove = "mover a move to".contains(needle) || needle.hasPrefix("mover") || needle.hasPrefix("move")
            for space in spaces where space.id != activeSpaceID
                && (wantsMove || space.name.searchNormalized.hasPrefix(needle)) {
                results.append(Suggestion(id: "move:\(space.id)", title: "Mover pestaña a «\(space.name)»",
                                          action: .moveTabToSpace(space.id), symbol: "arrow.right.square"))
            }
        }
        for command in commands.weak.prefix(2) { results.append(commandSuggestion(command)) }

        // 7. Sugerencias de búsqueda.
        for term in searchSuggestions.prefix(4) where term.searchNormalized != needle {
            guard let url = URLInput.searchURL(for: term) else { continue }
            add(Suggestion(id: "suggest:\(term)", title: term, action: .open(url), symbol: "magnifyingglass"))
        }

        return Array(results.prefix(12))
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
        case .moveTabToSpace(let id):
            if let tab = selectedTab, let space = spaces.first(where: { $0.id == id }) { move(tab, toSpace: space) }
        case .openFolder(let id):
            if let folder = folder(withID: id) {
                folder.isExpanded = true
                activeSpace.isPinnedCollapsed = false
                scheduleSave()
            }
        }
    }

    /// Comandos disponibles que coinciden, de más a menos relevante. Son "fuertes" si alguna
    /// palabra empieza por lo escrito: primero en el título, luego en las palabras clave.
    private func matchingCommands(_ needle: String) -> (strong: [BrowserCommand], weak: [BrowserCommand]) {
        guard needle.count >= 2 else { return ([], []) }
        func words(_ text: String) -> [String] {
            text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        var scored: [(BrowserCommand, Int)] = [], weak: [BrowserCommand] = []
        for command in BrowserCommand.allCases where command.isAvailable(in: self) {
            let title = command.title.searchNormalized
            let keywords = command.keywords.searchNormalized
            if title.hasPrefix(needle) { scored.append((command, 3)) }
            else if words(title).contains(where: { $0.hasPrefix(needle) }) { scored.append((command, 2)) }
            else if keywords.hasPrefix(needle) || words(keywords).contains(where: { $0.hasPrefix(needle) })
                || (needle.contains(" ") && keywords.contains(needle)) { scored.append((command, 1)) }
            else if title.contains(needle) || keywords.contains(needle) { weak.append(command) }
        }
        // `sorted` es estable: a igual puntuación se respeta el orden de la lista.
        let strong = scored.enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
            .map(\.element.0)
        return (strong, weak)
    }

    private func commandSuggestion(_ command: BrowserCommand) -> Suggestion {
        Suggestion(id: "command:\(command.rawValue)", title: command.title, action: .command(command),
                   symbol: command.symbol, shortcut: command.shortcut)
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
