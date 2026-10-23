import AppKit

// Acciones de los atajos de Arc y del menú de cada espacio.
extension Browser {
    // MARK: - Buscar en la página (⌘F, ⌘G, ⇧⌘G)

    public func showFindBar() {
        isFindBarVisible = true
    }

    public func findNext() {
        isFindBarVisible = true
        findRequest = FindRequest(direction: 1)
    }

    public func findPrevious() {
        isFindBarVisible = true
        findRequest = FindRequest(direction: -1)
    }

    // MARK: - Moverse entre pestañas

    /// Pestañas en el orden en que se ven: favoritos, fijadas (y carpetas abiertas) y las de hoy.
    public var sidebarOrderedTabs: [BrowserTab] {
        let space = activeSpace
        let pinned = space.pinned.flatMap { item -> [BrowserTab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.isExpanded ? folder.tabs : []
            }
        }
        return favorites + pinned + space.tabs
    }

    /// ⌘1…⌘8: la pestaña número `index` (empezando en 0).
    public func selectTab(at index: Int) {
        let tabs = sidebarOrderedTabs
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    /// ⌘9: la última pestaña.
    public func selectLastTab() {
        if let last = sidebarOrderedTabs.last { select(last) }
    }

    /// ⌥⌘↓ / ⌥⌘↑: siguiente o anterior en la barra lateral (da la vuelta).
    public func selectAdjacentTab(_ offset: Int) {
        let tabs = sidebarOrderedTabs
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == selectedTab?.id } ?? -1
        let next = (current + offset + tabs.count) % tabs.count
        select(tabs[next])
    }

    /// ⌃Tab: vuelve a la pestaña usada justo antes.
    public func selectRecentTab() {
        let candidates = sidebarOrderedTabs.filter { $0.id != selectedTab?.id }
        if let recent = candidates.max(by: { $0.lastActiveAt < $1.lastActiveAt }) { select(recent) }
    }

    // MARK: - Espacios

    /// ⌥⌘→ / ⌥⌘←: espacio siguiente o anterior.
    public func activateAdjacentSpace(_ offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let next = index + offset
        guard spaces.indices.contains(next) else { return }
        activate(spaces[next])
    }

    public func rename(_ space: Space, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        space.name = trimmed
        scheduleSave()
    }

    public func setIcon(_ icon: String, for space: Space) {
        space.icon = icon
        scheduleSave()
    }

    public func setTheme(_ theme: SpaceTheme, for space: Space) {
        space.theme = theme
        scheduleSave()
    }

    public func moveSpaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = spaces
        let moving = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) { reordered.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: min(insertAt, reordered.count))
        replaceSpaces(reordered)
    }

    /// Borra el espacio; sus pestañas van al archivo. Siempre queda al menos un espacio.
    public func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        for tab in space.allTabs {
            tab.hibernate()
            if let url = tab.url {
                insertIntoArchive(ArchivedTab(id: tab.id, url: url, title: tab.displayTitle, closedAt: Date()))
            }
        }
        var remaining = spaces
        remaining.remove(at: index)
        replaceSpaces(remaining)
        if activeSpaceID == space.id {
            activate(remaining[min(index, remaining.count - 1)])
        }
    }

    /// "Exportar «X» a una carpeta": copia las pestañas del espacio en una carpeta de otro espacio.
    public func export(_ space: Space, intoFolderIn target: Space) {
        let copies = space.allTabs.map { copyTab($0) }
        let folder = Folder(name: space.name, isExpanded: false, tabs: copies)
        target.pinned.append(.folder(folder))
        scheduleSave()
    }

    /// Mueve la pestaña a las de Hoy de otro espacio y se va con ella.
    public func move(_ tab: BrowserTab, toSpace space: Space) {
        detach(tab)
        space.tabs.insert(tab, at: 0)
        space.selectedTabID = tab.id
        activate(space)
        scheduleSave()
    }

    // MARK: - Perfiles

    public func profileName(_ id: UUID?) -> String {
        profiles.first { $0.id == id }?.name ?? "Predeterminado"
    }

    @discardableResult
    public func addProfile(named name: String) -> Profile {
        let profile = Profile(name: name)
        setProfiles(profiles + [profile])
        return profile
    }

    /// Cambia el perfil del espacio. Sus pestañas se recargan con las cookies del nuevo perfil.
    public func setProfile(_ profileID: UUID?, for space: Space) {
        guard space.profileID != profileID else { return }
        space.profileID = profileID
        for tab in space.allTabs { tab.discardPage() }
        showSelectedTab()
        scheduleSave()
    }

    public func deleteProfile(_ profile: Profile) {
        for space in spaces where space.profileID == profile.id {
            setProfile(nil, for: space)
        }
        setProfiles(profiles.filter { $0.id != profile.id })
        removeProfileData(profile.id)
    }

    /// Perfil de la pestaña: el del espacio que la contiene (los favoritos usan el predeterminado).
    func profileID(forTabID id: UUID) -> UUID? {
        spaces.first { $0.allTabs.contains { $0.id == id } }?.profileID
    }

    // MARK: - Copiar

    /// ⌥⇧⌘C: copia el enlace como Markdown, `[título](url)`.
    public func copyURLAsMarkdown() {
        guard let tab = selectedTab, let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(tab.displayTitle)](\(url.absoluteString))", forType: .string)
    }
}
