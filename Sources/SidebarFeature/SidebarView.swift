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
    @State private var listController = SidebarListController()
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

            // La lista es nativa (AppKit): sus animaciones no recalculan nada por fotograma.
            SidebarListView(browser: browser, space: space, theme: theme, controller: listController)
                .id(space.id)
                .transition(.push(from: spaceTransitionEdge))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SidebarDrag.space)) } action: { listController.frame = $0 }
                .onAppear { listController.onScrollChange = { scrolled in withAnimation(Theme.spring) { isScrolled = scrolled } } }
                .overlay(alignment: .top) {
                    if isScrolled {
                        Button {
                            listController.scrollToTop()
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
                SidebarMenus.copyLink(tab),
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
struct FolderPreview: View {
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
