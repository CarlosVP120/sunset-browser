import SwiftUI
import BrowserCore
import BrowserUI

/// Barra lateral vertical: favoritos, espacio, pestañas fijadas y carpetas, pestañas de hoy y espacios.
public struct SidebarView: View {
    let browser: Browser

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        let space = browser.activeSpace

        VStack(spacing: 0) {
            TopRow(browser: browser)

            if !browser.showsToolbar {
                SidebarURLField(browser: browser)
                    .padding(.bottom, 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !browser.favorites.isEmpty {
                        FavoritesGrid(browser: browser)
                            .padding(.bottom, 10)
                    }

                    SpaceHeader(space: space)

                    ForEach(space.pinned) { item in
                        switch item {
                        case .tab(let tab):
                            TabRow(browser: browser, tab: tab)
                        case .folder(let folder):
                            FolderRow(browser: browser, folder: folder)
                        }
                    }

                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                    NewTabRow(browser: browser)

                    ForEach(space.tabs) { tab in
                        TabRow(browser: browser, tab: tab)
                    }
                }
                .padding(.bottom, 8)
            }
            .id(space.id)
            .transition(.opacity)

            BottomBar(browser: browser)
        }
        .padding(.horizontal, 8)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: browser.activeSpaceID)
    }
}

// MARK: - Cabecera

/// Fila superior: deja sitio a los botones de la ventana y muestra el botón de la barra lateral.
private struct TopRow: View {
    let browser: Browser

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { browser.showsSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Ocultar la barra lateral (⌘S)")

            if !browser.showsToolbar {
                Spacer()
                NavigationButtons(tab: browser.selectedTab)
            }
            Spacer()
        }
        .buttonStyle(ChromeButtonStyle())
        .padding(.leading, Theme.windowButtonsInset - 8)
        .frame(height: Theme.toolbarHeight)
    }
}

/// Campo de URL en la barra lateral, cuando la barra superior está oculta.
private struct SidebarURLField: View {
    let browser: Browser
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Buscar o escribir una URL", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.primaryText)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.tile))
            .onSubmit {
                browser.navigate(to: text)
                isFocused = false
            }
            .onExitCommand {
                isFocused = false
                syncText()
            }
            .onChange(of: browser.urlFocusRequests) {
                text = ""
                isFocused = true
            }
            .onChange(of: browser.selectedTab?.url, initial: true) { if !isFocused { syncText() } }
            .onChange(of: browser.activeSpaceID) { syncText() }
    }

    private func syncText() {
        text = browser.selectedTab?.url?.absoluteString ?? ""
    }
}

private struct SpaceHeader: View {
    let space: Space

    var body: some View {
        HStack(spacing: 8) {
            SpaceIcon(space.icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text(space.name)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

// MARK: - Favoritos

private struct FavoritesGrid: View {
    let browser: Browser

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(browser.favorites) { tab in
                FavoriteTile(browser: browser, tab: tab)
            }
        }
    }
}

private struct FavoriteTile: View {
    let browser: Browser
    let tab: BrowserTab
    @State private var isHovering = false

    var body: some View {
        let isSelected = browser.selectedTab?.id == tab.id

        FaviconView(tab: tab, size: 18)
            .opacity(tab.isHibernated && !isSelected ? 0.75 : 1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.selected : (isHovering ? Theme.tile.opacity(1.6) : Theme.tile))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.12 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { browser.select(tab) }
            .onHover { isHovering = $0 }
            .help(tab.displayTitle)
            .contextMenu {
                Button("Quitar de favoritos") { browser.removeFromFavorites(tab) }
                CopyLinkButton(tab: tab)
                Divider()
                Button("Descargar de memoria") { browser.close(tab) }
            }
    }
}

// MARK: - Filas

private struct TabRow: View {
    let browser: Browser
    let tab: BrowserTab
    var indent: CGFloat = 0
    @State private var isHovering = false

    var body: some View {
        let space = browser.activeSpace
        let isSelected = browser.selectedTab?.id == tab.id
        let isPinned = space.isPinned(tab)

        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.primaryText.opacity(tab.isHibernated && !isSelected ? 0.75 : 1))
            Spacer(minLength: 0)
            if isHovering {
                Button { browser.close(tab) } label: {
                    Image(systemName: isPinned ? "minus" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(ChromeButtonStyle(size: 20))
                .help(isPinned ? "Descargar de memoria" : "Cerrar pestaña")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 10 + indent)
        .padding(.trailing, 6)
        .frame(height: Theme.rowHeight)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .contentShape(Rectangle())
        .onTapGesture { browser.select(tab) }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Añadir a favoritos") { browser.addToFavorites(tab) }
            Button(isPinned ? "Desfijar" : "Fijar") { browser.togglePin(tab) }
            if !space.folders.isEmpty {
                Menu("Mover a carpeta") {
                    ForEach(space.folders) { folder in
                        Button(folder.name) { browser.move(tab, to: folder) }
                    }
                }
            }
            CopyLinkButton(tab: tab)
            Divider()
            Button("Cerrar pestaña") { browser.close(tab) }
        }
    }
}

private struct FolderRow: View {
    let browser: Browser
    let folder: Folder
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: folder.isExpanded ? "folder" : "folder.fill")
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
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: Theme.rowHeight)
            .background(RowBackground(isSelected: false, isHovering: isHovering))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { browser.toggle(folder) }
            }
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Renombrar") {
                    newName = folder.name
                    isRenaming = true
                }
                Button("Eliminar carpeta") { browser.delete(folder) }
            }

            if folder.isExpanded {
                ForEach(folder.tabs) { tab in
                    TabRow(browser: browser, tab: tab, indent: 14)
                }
            }
        }
    }
}

private struct NewTabRow: View {
    let browser: Browser
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text("Nueva pestaña")
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(RowBackground(isSelected: false, isHovering: isHovering))
        .contentShape(Rectangle())
        .onTapGesture { browser.newTab() }
        .onHover { isHovering = $0 }
    }
}

private struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(isSelected ? Theme.selected : (isHovering ? Theme.hover : .clear))
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 2, y: 1)
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

    var body: some View {
        HStack(spacing: 4) {
            Button { showsArchive.toggle() } label: {
                Image(systemName: "archivebox")
            }
            .help("Archivo de pestañas cerradas")
            .popover(isPresented: $showsArchive, arrowEdge: .top) {
                ArchiveList(browser: browser) { showsArchive = false }
            }

            Spacer()

            ForEach(browser.spaces) { space in
                let isActive = space.id == browser.activeSpaceID
                Button { browser.activate(space) } label: {
                    SpaceIcon(space.icon, filled: isActive)
                        .font(.system(size: isActive ? 12 : 11))
                        .opacity(isActive ? 1 : 0.55)
                }
                .help(space.name)
            }

            Spacer()

            Menu {
                Button("Nueva pestaña") { browser.newTab() }
                Button("Nueva carpeta") { browser.newFolder() }
                Divider()
                Button("Nuevo espacio") { browser.addSpace(name: "Espacio \(browser.spaces.count + 1)") }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.primaryText.opacity(0.8))
            .help("Nuevo")
        }
        .buttonStyle(ChromeButtonStyle())
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archived.title).lineLimit(1)
                            Text(archived.url.host() ?? archived.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
