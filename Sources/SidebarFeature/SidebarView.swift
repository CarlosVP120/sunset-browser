import SwiftUI
import BrowserCore
import BrowserUI

/// Barra lateral vertical: favoritos, espacio, pestañas fijadas y carpetas, pestañas de hoy y espacios.
public struct SidebarView: View {
    let browser: Browser
    /// Lo que la app añade arriba a la derecha (los botones de extensiones).
    let accessory: AnyView?
    /// Botón de abajo a la izquierda (la Librería); si no hay, el archivo de pestañas cerradas.
    let libraryButton: AnyView?
    /// Hacia dónde se desliza el contenido al cambiar de espacio.
    @State private var spaceTransitionEdge: Edge = .trailing
    @State private var isScrolled = false
    @State private var drag = SidebarDrag()
    @Environment(\.spaceTheme) private var theme

    private static let topID = "sidebar-top"
    private static let scrollSpace = "sidebar-scroll"

    public init(browser: Browser, accessory: AnyView? = nil, libraryButton: AnyView? = nil) {
        self.browser = browser
        self.accessory = accessory
        self.libraryButton = libraryButton
    }

    public var body: some View {
        let space = browser.activeSpace

        VStack(spacing: 0) {
            TopRow(browser: browser, accessory: accessory)

            if !browser.showsToolbar {
                AddressButton(browser: browser, style: .sidebar)
                    .padding(.bottom, 8)
            }

            // Los favoritos no se mueven al hacer scroll (como en Arc). Si aún no hay, al arrastrar
            // aparece un hueco para soltar ahí la primera.
            if !browser.favorites.isEmpty {
                FavoritesGrid(browser: browser)
                    .padding(.bottom, 10)
            } else if drag.isDragging {
                EmptyFavoritesDrop(browser: browser)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Color.clear.frame(height: 0).id(Self.topID)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: ScrollOffsetKey.self,
                                                       value: geometry.frame(in: .named(Self.scrollSpace)).minY)
                            })
                        SpaceContent(browser: browser, space: space)
                            .id(space.id)
                            .transition(.push(from: spaceTransitionEdge))
                    }
                    .padding(.bottom, 8)
                }
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    let scrolled = offset < -60
                    if scrolled != isScrolled { withAnimation(Theme.spring) { isScrolled = scrolled } }
                }
                // Al hacer scroll, el contenido se funde bajo los favoritos en vez de cortarse.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(isScrolled ? 0 : 1), .black],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                        Color.black
                    }
                )
                .overlay(alignment: .top) {
                    if isScrolled {
                        Button {
                            withAnimation(Theme.spring) { proxy.scrollTo(Self.topID, anchor: .top) }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(white: 0.12))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.92)))
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .tooltip("Volver arriba")
                        .padding(.top, 4)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            }

            // Reproductores de lo que suena en otras pestañas (como en Arc). Va en su propia vista
            // para que sus cambios no redibujen toda la barra lateral (ni sus menús abiertos).
            MediaPlayersSection(browser: browser)

            BottomBar(browser: browser, libraryButton: libraryButton)
        }
        .padding(.horizontal, 8)
        .coordinateSpace(name: SidebarDrag.space)
        .overlay(alignment: .topLeading) {
            if let ghost = drag.ghost {
                DragGhost(ghost: ghost)
                    .offset(x: drag.location.x - 24, y: drag.location.y - 17)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .environment(drag)
        .animation(Theme.spring, value: drag.isDragging)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .onChange(of: browser.activeSpaceID) { oldID, newID in
            let oldIndex = browser.spaces.firstIndex { $0.id == oldID } ?? 0
            let newIndex = browser.spaces.firstIndex { $0.id == newID } ?? 0
            spaceTransitionEdge = newIndex >= oldIndex ? .trailing : .leading
        }
        .animation(Theme.spring, value: browser.activeSpaceID)
    }
}

private struct MediaPlayersSection: View {
    let browser: Browser

    var body: some View {
        let tabs = browser.backgroundMediaTabs
        VStack(spacing: 6) {
            ForEach(tabs.prefix(2)) { tab in
                MediaPlayerCard(browser: browser, tab: tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, tabs.isEmpty ? 0 : 6)
        .animation(Theme.spring, value: tabs.map(\.id))
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Lo que cambia con el espacio: cabecera, fijadas, separador, nueva pestaña y pestañas de hoy.
private struct SpaceContent: View {
    let browser: Browser
    let space: Space
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SpaceHeader(browser: browser, space: space)
                .sidebarDropTarget { size, zone in
                    SidebarDropDelegate(browser: browser, size: size,
                                        location: { _ in .pinned(0) },
                                        folderIndex: { _ in 0 }, zone: zone)
                }

            ForEach(Array((space.isPinnedCollapsed ? [] : space.pinned).enumerated()), id: \.element.id) { index, item in
                switch item {
                case .tab(let tab):
                    TabRow(browser: browser, tab: tab)
                        .sidebarDropTarget { size, zone in
                            SidebarDropDelegate(
                                browser: browser, size: size,
                                location: { $0 == .before ? .pinned(index) : .pinned(index + 1) },
                                folderIndex: { $0 == .before ? index : index + 1 },
                                zone: zone
                            )
                        }
                case .folder(let folder):
                    FolderSection(browser: browser, folder: folder, pinnedIndex: index)
                }
            }

            TodaySeparator(browser: browser, space: space)

            NewTabRow(browser: browser)
                .sidebarDropTarget { size, zone in
                    SidebarDropDelegate(browser: browser, size: size, location: { _ in .today(0) }, zone: zone)
                }

            ForEach(Array(space.tabs.enumerated()), id: \.element.id) { index, tab in
                TabRow(browser: browser, tab: tab)
                    .sidebarDropTarget { size, zone in
                        SidebarDropDelegate(
                            browser: browser, size: size,
                            location: { $0 == .before ? .today(index) : .today(index + 1) },
                            zone: zone
                        )
                    }
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.95))))
            }
        }
        .animation(Theme.spring, value: space.tabs.map(\.id))
        .animation(Theme.spring, value: space.pinned.map(\.id))
        .animation(Theme.spring, value: space.isPinnedCollapsed)
    }
}

/// Separador entre fijadas y Hoy. Al pasar el ratón aparece "Limpiar" (archiva las de Hoy).
private struct TodaySeparator: View {
    let browser: Browser
    let space: Space
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(theme.title).opacity(0.10))
                .frame(height: 1)
            if isHovering && !space.tabs.isEmpty {
                Button {
                    withAnimation(Theme.spring) { browser.archiveTodayTabs(keepingSelected: false) }
                } label: {
                    Text("Limpiar")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .buttonStyle(PillButtonStyle())
                .tooltip("Archivar las pestañas de Hoy")
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
    }
}

// MARK: - Cabecera

/// Fila superior: deja sitio a los botones de la ventana y muestra el botón de la barra lateral.
private struct TopRow: View {
    let browser: Browser
    let accessory: AnyView?

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(Theme.spring) { browser.showsSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .tooltip("Ocultar barra lateral", shortcut: "⌘S")

            Spacer()
            if !browser.showsToolbar {
                NavigationButtons(tab: browser.selectedTab)
            }
            if let accessory { accessory }
        }
        .buttonStyle(ChromeButtonStyle())
        .padding(.leading, Theme.windowButtonsInset - 8)
        .frame(height: Theme.toolbarHeight)
    }
}

// MARK: - Favoritos

private struct FavoritesGrid: View {
    let browser: Browser

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(Array(browser.favorites.enumerated()), id: \.element.id) { index, tab in
                FavoriteTile(browser: browser, tab: tab)
                    .sidebarDropTarget({ size, zone in
                        SidebarDropDelegate(
                            browser: browser, horizontal: true, size: size,
                            location: { $0 == .before ? .favorites(index) : .favorites(index + 1) },
                            zone: zone
                        )
                    }, horizontal: true)
            }
        }
        .animation(Theme.spring, value: browser.favorites.map(\.id))
    }
}

private struct FavoriteTile: View {
    let browser: Browser
    let tab: BrowserTab

    var body: some View {
        let isSelected = browser.selectedTab?.id == tab.id

        Button { browser.select(tab) } label: {
            LoadingFavicon(tab: tab, size: 18)
                .opacity(tab.isHibernated && !isSelected ? 0.8 : 1)
        }
        .buttonStyle(FavoriteTileStyle(isSelected: isSelected))
        .tooltip(tab.displayTitle)
        .sidebarDraggable(.tab(tab.id)) { .init(pageURL: tab.url, faviconURL: tab.faviconURL, title: tab.displayTitle, symbol: nil) }
        .nativeContextMenu {
            [
                .button("Quitar de favoritos") { browser.removeFromFavorites(tab) },
                copyLinkEntry(tab),
                .separator,
                .button("Descargar de memoria") { browser.close(tab) },
            ]
        }
    }
}

private struct FavoriteTileStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, isSelected: isSelected)
    }

    private struct Tile: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.spaceTheme) private var theme
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(isSelected ? theme.focus : theme.hover))
                        .opacity(isSelected ? 1 : (isHovering ? 0.95 : 0.45))
                        .shadow(color: .black.opacity(isSelected ? 0.2 : 0), radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.14 : 0), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(Theme.pressSpring, value: configuration.isPressed)
                .animation(Theme.spring, value: isSelected)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering }
                }
        }
    }
}

// MARK: - Filas

private struct TabRow: View {
    let browser: Browser
    let tab: BrowserTab
    var indent: CGFloat = 0
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        let space = browser.activeSpace
        let isSelected = browser.selectedTab?.id == tab.id
        let isPinned = space.isPinned(tab)

        Button { browser.select(tab) } label: {
            TabRowLabel(browser: browser, tab: tab, isSelected: isSelected, isPinned: isPinned)
                .padding(.leading, 10 + indent)
                .padding(.trailing, 4)
        }
        .buttonStyle(SidebarRowStyle(isSelected: isSelected, height: tab.isDeveloperMode ? 44 : Theme.rowHeight))
        // Modo desarrollador (como en Arc): borde punteado amarillo alrededor de la pestaña.
        .overlay {
            if tab.isDeveloperMode {
                RoundedRectangle(cornerRadius: Theme.cornerRadius + 2, style: .continuous)
                    .strokeBorder(Color(red: 1.0, green: 0.82, blue: 0.22).opacity(0.9),
                                  style: StrokeStyle(lineWidth: 1.6, dash: [4.5, 3.5]))
                    .padding(-1)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: tab.isDeveloperMode)
        .sidebarDraggable(.tab(tab.id)) { .init(pageURL: tab.url, faviconURL: tab.faviconURL, title: tab.displayTitle, symbol: nil) }
        .nativeContextMenu { menuEntries() }
    }

    private func menuEntries() -> [MenuEntry] {
        let space = browser.activeSpace
        var entries: [MenuEntry] = [.button("Renombrar…") { browser.renamingTabID = tab.id }]
        if tab.customTitle != nil {
            entries.append(.button("Restablecer nombre") { browser.rename(tab, to: "") })
        }
        entries += [
            .button("Duplicar") {
                browser.select(tab)
                browser.perform(.duplicateTab)
            },
            .separator,
            .button("Añadir a favoritos") { browser.addToFavorites(tab) },
            .button(space.isPinned(tab) ? "Desfijar" : "Fijar") { withAnimation(Theme.spring) { browser.togglePin(tab) } },
        ]
        if !space.folders.isEmpty {
            entries.append(.menu("Mover a carpeta", space.folders.map { folder in
                .button(folder.name) { withAnimation(Theme.spring) { browser.move(tab, to: .folder(folder, folder.tabs.count)) } }
            }))
        }
        entries += [
            copyLinkEntry(tab),
            .separator,
            .button("Cerrar pestaña") { withAnimation(Theme.spring) { browser.close(tab) } },
        ]
        return entries
    }
}

private struct TabRowLabel: View {
    let browser: Browser
    let tab: BrowserTab
    let isSelected: Bool
    let isPinned: Bool
    @State private var newName = ""
    @FocusState private var isNameFocused: Bool
    @Environment(\.rowIsHovering) private var isHovering
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            LoadingFavicon(tab: tab)
            if tab.isAwayFromPinned {
                // Como en Arc: la fijada se movió de su dirección. Pulsar la "/" la devuelve.
                Button { browser.returnToPinnedURL(tab) } label: {
                    Text("/")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.6))
                        .padding(.horizontal, 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tooltip("Volver a \(tab.pinnedURL?.host() ?? "la dirección fijada")")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            if browser.renamingTabID == tab.id {
                TextField(tab.title, text: $newName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color(theme.title))
                    .focused($isNameFocused)
                    .onAppear {
                        newName = tab.displayTitle
                        isNameFocused = true
                    }
                    .onSubmit { browser.rename(tab, to: newName) }
                    .onExitCommand { browser.renamingTabID = nil }
                    .onChange(of: isNameFocused) {
                        if !isNameFocused, browser.renamingTabID == tab.id { browser.rename(tab, to: newName) }
                    }
            } else {
                // El título usa todo el ancho y se desvanece al final; al pasar el ratón,
                // el desvanecido se alarga para dejar sitio al botón de cerrar.
                VStack(alignment: .leading, spacing: 1) {
                    FadingText(tab.displayTitle, fade: 14, trailingClear: isHovering ? 24 : 0)
                        .foregroundStyle(Color(theme.title).opacity(tab.isHibernated && !isSelected ? 0.72 : 1))
                        .animation(Theme.hoverOut, value: isHovering)
                    if tab.isDeveloperMode {
                        // En modo desarrollador se ve el servidor (p. ej. "localhost:3005").
                        FadingText(DeveloperMode.hostAndPort(tab.url), fade: 14, trailingClear: isHovering ? 24 : 0)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            // El botón no ocupa sitio: solo aparece encima del final del título.
            if isHovering && browser.renamingTabID != tab.id {
                Button { withAnimation(Theme.spring) { browser.close(tab) } } label: {
                    Image(systemName: isPinned ? "minus" : "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .buttonStyle(ChromeButtonStyle(size: 22))
                .tooltip(isPinned ? (tab.isAwayFromPinned ? "Volver a la dirección fijada" : "Descargar de memoria") : "Cerrar pestaña",
                         shortcut: "⌘W")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(Theme.hoverIn, value: isHovering)
        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
        .animation(Theme.spring, value: tab.isLoading)
        .animation(Theme.spring, value: tab.isAwayFromPinned)
    }
}

private struct FolderSection: View {
    let browser: Browser
    let folder: Folder
    let pinnedIndex: Int
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var showsPreview = false
    @State private var isOverRow = false
    @State private var isOverPopover = false
    @State private var previewTask: Task<Void, Never>?
    /// Cuántas filas de la carpeta existen ahora (se crean por tandas al abrir).
    @State private var mountedCount = 0
    @Environment(SidebarDrag.self) private var drag

    /// Altura de la carpeta abierta: la suma de sus filas (cada una mide siempre lo mismo).
    private var expandedHeight: CGFloat {
        guard !folder.tabs.isEmpty else { return 0 }
        let rows = folder.tabs.reduce(CGFloat(0)) { $0 + ($1.isDeveloperMode ? 44 : Theme.rowHeight) }
        return rows + CGFloat(folder.tabs.count - 1) * 2
    }

    /// Al abrir, crea las filas de 6 en 6 en cada fotograma; al cerrar, las suelta cuando termina
    /// la animación (si sigue cerrada).
    private func mountRows() async {
        if folder.isExpanded {
            while mountedCount < folder.tabs.count, !Task.isCancelled {
                mountedCount = min(folder.tabs.count, mountedCount + 6)
                try? await Task.sleep(for: .milliseconds(8))
            }
        } else if mountedCount > 0 {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled, !folder.isExpanded { mountedCount = 0 }
        }
    }
    @Environment(\.spaceTheme) private var theme

    /// Abre la vista previa tras un momento sobre la fila y la cierra al salir de fila y vista previa.
    private func previewHover(row: Bool? = nil, popover: Bool? = nil) {
        if let row { isOverRow = row }
        if let popover { isOverPopover = popover }
        previewTask?.cancel()
        let wantsOpen = isOverRow || isOverPopover
        guard wantsOpen != showsPreview, !folder.tabs.isEmpty, !drag.isDragging, !isRenaming else { return }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(wantsOpen ? 650 : 250))
            guard !Task.isCancelled, !drag.isDragging else { return }
            showsPreview = wantsOpen
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Button {
                previewTask?.cancel()
                showsPreview = false
                withAnimation(Theme.spring) { browser.toggle(folder) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: folder.isExpanded ? "folder" : "folder.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 12))
                        .frame(width: 16)
                    if isRenaming {
                        TextField("Nombre", text: $newName)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                browser.rename(folder, to: newName.isEmpty ? folder.name : newName)
                                isRenaming = false
                            }
                            .onExitCommand { isRenaming = false }
                    } else {
                        FadingText(folder.name)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.title))
                .padding(.horizontal, 10)
            }
            .buttonStyle(SidebarRowStyle(isSelected: false))
            // Como en Arc: al quedarte sobre una carpeta, se abre al lado una vista previa con buscador.
            .onHover { hovering in previewHover(row: hovering) }
            .popover(isPresented: $showsPreview, arrowEdge: .trailing) {
                FolderPreview(browser: browser, folder: folder) { showsPreview = false }
                    .onHover { hovering in previewHover(popover: hovering) }
            }
            .sidebarDraggable(.folder(folder.id)) { .init(pageURL: nil, faviconURL: nil, title: folder.name, symbol: "folder.fill") }
            .sidebarDropTarget { size, zone in
                SidebarDropDelegate(
                    browser: browser, acceptsInside: true, size: size,
                    location: { zone in
                        switch zone {
                        case .before: .pinned(pinnedIndex)
                        case .inside: .folder(folder, folder.tabs.count)
                        case .after: folder.isExpanded ? .folder(folder, 0) : .pinned(pinnedIndex + 1)
                        }
                    },
                    folderIndex: { $0 == .before ? pinnedIndex : pinnedIndex + 1 },
                    zone: zone
                )
            }
            .nativeContextMenu {
                [
                    .button("Renombrar") {
                        newName = folder.name
                        isRenaming = true
                    },
                    .button("Eliminar carpeta") { withAnimation(Theme.spring) { browser.delete(folder) } },
                ]
            }

            // Como una lista nativa: la carpeta sabe su altura final desde el primer momento (las
            // filas miden siempre lo mismo) y la anima; las filas se crean por tandas, fotograma a
            // fotograma, mientras se descubren. Antes se creaban todas de golpe al abrir (con 30
            // pestañas, un fotograma de más de 70 ms: el tirón del principio).
            VStack(spacing: 2) {
                ForEach(Array(folder.tabs.prefix(mountedCount).enumerated()), id: \.element.id) { index, tab in
                    TabRow(browser: browser, tab: tab, indent: 14)
                        .sidebarDropTarget { size, zone in
                            SidebarDropDelegate(
                                browser: browser, size: size,
                                location: { $0 == .before ? .folder(folder, index) : .folder(folder, index + 1) },
                                zone: zone
                            )
                        }
                }
            }
            .frame(height: folder.isExpanded ? expandedHeight : 0, alignment: .top)
            .clipped()
            .opacity(folder.isExpanded ? 1 : 0)
            .allowsHitTesting(folder.isExpanded)
            .task(id: folder.isExpanded) { await mountRows() }
        }
        .clipped()
        .animation(Theme.spring, value: folder.tabs.map(\.id))
    }
}

private struct NewTabRow: View {
    let browser: Browser
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Button { withAnimation(Theme.spring) { browser.openHome() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text("Nueva pestaña")
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(theme.subtitle).opacity(1.5))
            .padding(.horizontal, 10)
        }
        .buttonStyle(SidebarRowStyle(isSelected: false))
        .tooltip("Nueva pestaña en Inicio (⌘T abre el Command Bar)")
    }
}

@MainActor
private func copyLinkEntry(_ tab: BrowserTab) -> MenuEntry {
    .button("Copiar enlace", enabled: tab.url != nil) {
        guard let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

// MARK: - Barra inferior

private struct BottomBar: View {
    let browser: Browser
    let libraryButton: AnyView?
    @State private var showsArchive = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if let libraryButton {
                libraryButton
            } else {
                Button { showsArchive.toggle() } label: {
                    Image(systemName: "archivebox")
                }
                .tooltip("Pestañas cerradas", shortcut: "⇧⌘T")
                .popover(isPresented: $showsArchive, arrowEdge: .top) {
                    ArchiveList(browser: browser) { showsArchive = false }
                }
            }

            Spacer()

            ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                let isActive = space.id == browser.activeSpaceID
                Button { browser.activate(space) } label: {
                    SpaceIcon(space.icon, filled: isActive)
                        .font(.system(size: 11.5))
                        .opacity(isActive ? 1 : 0.5)
                        .scaleEffect(isActive ? 1.1 : 1)
                }
                .tooltip(space.name, shortcut: index < 9 ? "⌃\(index + 1)" : nil)
                .nativeContextMenu { SpaceMenu.entries(browser: browser, space: space) }
                // Soltar una pestaña en el icono de un espacio la manda a ese espacio (como en Arc).
                .sidebarDropTarget { size, zone in
                    SidebarDropDelegate(browser: browser, acceptsInside: true, size: size, location: { _ in nil },
                                        onTab: { tab in browser.move(tab, toSpace: space) }, zone: zone)
                }
            }

            Spacer()

            Menu {
                Button("Nueva pestaña") { withAnimation(Theme.spring) { browser.openHome() } }
                Button("Nueva carpeta") { withAnimation(Theme.spring) { _ = browser.newFolder() } }
                Divider()
                Button("Nuevo espacio") { browser.addSpace(name: "Espacio \(browser.spaces.count + 1)") }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Color(theme.title).opacity(0.85))
            .tooltip("Nuevo")
        }
        .buttonStyle(ChromeButtonStyle())
        .animation(Theme.spring, value: browser.activeSpaceID)
        .frame(height: 38)
    }
}

private struct ArchiveList: View {
    let browser: Browser
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Archivo").font(.headline)
                Spacer()
                Button("Vaciar") { browser.clearArchive() }
                    .disabled(browser.archive.isEmpty)
            }
            .padding(12)

            Divider()

            if browser.archive.isEmpty {
                Text("Aquí aparecerán las pestañas que cierres.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                List(browser.archive) { archived in
                    Button {
                        browser.restore(archived)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            FaviconView(pageURL: archived.url)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(archived.title).lineLimit(1)
                                Text(archived.url.host() ?? archived.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: 380)
    }
}

/// Hueco para soltar la primera favorita (solo aparece mientras arrastras).
private struct EmptyFavoritesDrop: View {
    let browser: Browser
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(theme.title).opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 50)
            .overlay(
                Label("Suelta aquí para fijarla arriba", systemImage: "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(theme.subtitle).opacity(1.5))
            )
            .sidebarDropTarget { size, zone in
                SidebarDropDelegate(browser: browser, size: size, location: { _ in .favorites(0) }, zone: zone)
            }
    }
}

/// Vista previa de una carpeta (como en Arc): buscador y sus pestañas, con cuándo las usaste.
private struct FolderPreview: View {
    let browser: Browser
    let folder: Folder
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool

    private var tabs: [BrowserTab] {
        let all = folder.tabs.sorted { $0.lastActiveAt > $1.lastActiveAt }
        guard !query.isEmpty else { return all }
        let needle = query.searchNormalized
        return all.filter { $0.displayTitle.searchNormalized.contains(needle) || ($0.url?.host() ?? "").searchNormalized.contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Buscar en \(folder.name)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFocused)
                    .onSubmit { open(at: highlighted) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(tabs.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                    .onChange(of: query) { highlighted = 0 }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        Button { open(at: index) } label: {
                            HStack(spacing: 11) {
                                FaviconView(tab: tab, size: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.displayTitle)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(tab.lastActiveAt == .distantPast
                                         ? (tab.url?.host() ?? "")
                                         : tab.lastActiveAt.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(index == highlighted ? 0.08 : 0)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = index } }
                    }
                    if tabs.isEmpty {
                        Text("Sin resultados").font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 330)
        }
        .frame(width: 330)
        .onAppear { isSearchFocused = true }
    }

    private func open(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        browser.select(tabs[index])
        close()
    }
}
