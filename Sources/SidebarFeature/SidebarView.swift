import SwiftUI
import BrowserCore
import BrowserUI

/// Barra lateral vertical: favoritos, espacio, pestañas fijadas y carpetas, pestañas de hoy y espacios.
public struct SidebarView: View {
    let browser: Browser
    /// Lo que la app añade arriba a la derecha (los botones de extensiones).
    let accessory: AnyView?
    /// Hacia dónde se desliza el contenido al cambiar de espacio.
    @State private var spaceTransitionEdge: Edge = .trailing
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, accessory: AnyView? = nil) {
        self.browser = browser
        self.accessory = accessory
    }

    public var body: some View {
        let space = browser.activeSpace

        VStack(spacing: 0) {
            TopRow(browser: browser, accessory: accessory)

            if !browser.showsToolbar {
                AddressButton(browser: browser, style: .sidebar)
                    .padding(.bottom, 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !browser.favorites.isEmpty {
                        FavoritesGrid(browser: browser)
                            .padding(.bottom, 10)
                    }

                    SpaceContent(browser: browser, space: space)
                        .id(space.id)
                        .transition(.push(from: spaceTransitionEdge))
                }
                .padding(.bottom, 8)
            }

            BottomBar(browser: browser)
        }
        .padding(.horizontal, 8)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .onChange(of: browser.activeSpaceID) { oldID, newID in
            let oldIndex = browser.spaces.firstIndex { $0.id == oldID } ?? 0
            let newIndex = browser.spaces.firstIndex { $0.id == newID } ?? 0
            spaceTransitionEdge = newIndex >= oldIndex ? .trailing : .leading
        }
        .animation(Theme.spring, value: browser.activeSpaceID)
    }
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

            ForEach(Array(space.pinned.enumerated()), id: \.element.id) { index, item in
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

            Rectangle()
                .fill(Color(theme.title).opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

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
        .onDrag { DragPayload.provider(for: tab) }
        .contextMenu {
            Button("Quitar de favoritos") { browser.removeFromFavorites(tab) }
            CopyLinkButton(tab: tab)
            Divider()
            Button("Descargar de memoria") { browser.close(tab) }
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
        .buttonStyle(SidebarRowStyle(isSelected: isSelected))
        .onDrag { DragPayload.provider(for: tab) }
        .contextMenu {
            Button("Añadir a favoritos") { browser.addToFavorites(tab) }
            Button(isPinned ? "Desfijar" : "Fijar") { withAnimation(Theme.spring) { browser.togglePin(tab) } }
            if !space.folders.isEmpty {
                Menu("Mover a carpeta") {
                    ForEach(space.folders) { folder in
                        Button(folder.name) { withAnimation(Theme.spring) { browser.move(tab, to: .folder(folder, folder.tabs.count)) } }
                    }
                }
            }
            CopyLinkButton(tab: tab)
            Divider()
            Button("Cerrar pestaña") { withAnimation(Theme.spring) { browser.close(tab) } }
        }
    }
}

private struct TabRowLabel: View {
    let browser: Browser
    let tab: BrowserTab
    let isSelected: Bool
    let isPinned: Bool
    @Environment(\.rowIsHovering) private var isHovering
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            LoadingFavicon(tab: tab)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color(theme.title).opacity(tab.isHibernated && !isSelected ? 0.72 : 1))
            Spacer(minLength: 0)
            Button { withAnimation(Theme.spring) { browser.close(tab) } } label: {
                Image(systemName: isPinned ? "minus" : "xmark")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .buttonStyle(ChromeButtonStyle(size: 22))
            .tooltip(isPinned ? "Descargar de memoria" : "Cerrar pestaña", shortcut: "⌘W")
            .opacity(isHovering ? 1 : 0)
            .scaleEffect(isHovering ? 1 : 0.7)
            .animation(Theme.hoverIn, value: isHovering)
        }
        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
        .animation(Theme.spring, value: tab.isLoading)
    }
}

private struct FolderSection: View {
    let browser: Browser
    let folder: Folder
    let pinnedIndex: Int
    @State private var isRenaming = false
    @State private var newName = ""
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Button {
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
                        Text(folder.name).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.title))
                .padding(.horizontal, 10)
            }
            .buttonStyle(SidebarRowStyle(isSelected: false))
            .onDrag { DragPayload.provider(for: folder.id) }
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
            .contextMenu {
                Button("Renombrar") {
                    newName = folder.name
                    isRenaming = true
                }
                Button("Eliminar carpeta") { withAnimation(Theme.spring) { browser.delete(folder) } }
            }

            if folder.isExpanded {
                VStack(spacing: 2) {
                    ForEach(Array(folder.tabs.enumerated()), id: \.element.id) { index, tab in
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .animation(Theme.spring, value: folder.tabs.map(\.id))
    }
}

private struct NewTabRow: View {
    let browser: Browser
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Button { browser.newTab() } label: {
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
        .tooltip("Nueva pestaña", shortcut: "⌘T")
    }
}

private struct CopyLinkButton: View {
    let tab: BrowserTab

    var body: some View {
        Button("Copiar enlace") {
            guard let url = tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
        .disabled(tab.url == nil)
    }
}

// MARK: - Barra inferior

private struct BottomBar: View {
    let browser: Browser
    @State private var showsArchive = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Button { showsArchive.toggle() } label: {
                Image(systemName: "archivebox")
            }
            .tooltip("Pestañas cerradas", shortcut: "⇧⌘T")
            .popover(isPresented: $showsArchive, arrowEdge: .top) {
                ArchiveList(browser: browser) { showsArchive = false }
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
                .contextMenu { SpaceMenu(browser: browser, space: space) }
            }

            Spacer()

            Menu {
                Button("Nueva pestaña") { browser.newTab() }
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
