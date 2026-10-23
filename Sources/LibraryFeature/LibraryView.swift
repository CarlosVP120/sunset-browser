import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import BrowserCore
import BrowserEngine
import BrowserUI

/// La Librería de Arc: ocupa el lugar de la barra lateral, con las secciones a la izquierda
/// (Media, Descargas, Espacios, Pestañas archivadas) y su contenido a la derecha.
public struct LibraryView: View {
    let browser: Browser
    let downloads: DownloadManager
    let passwords: PasswordVault?
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, downloads: DownloadManager, passwords: PasswordVault? = nil) {
        self.browser = browser
        self.downloads = downloads
        self.passwords = passwords
    }

    public var body: some View {
        HStack(spacing: 0) {
            SectionRail(browser: browser)
                .frame(width: 92)

            Group {
                switch browser.librarySection {
                case .downloads: DownloadsSection(downloads: downloads)
                case .media: MediaSection(downloads: downloads)
                case .spaces: SpacesSection(browser: browser)
                case .archive: ArchiveSection(browser: browser)
                case .passwords: PasswordsSection(browser: browser, vault: passwords)
                }
            }
            .id(browser.librarySection)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, Theme.toolbarHeight)
        .background {
            // Esc vuelve a la barra lateral.
            Button("") { withAnimation(Theme.spring) { browser.showsLibrary = false } }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .animation(Theme.spring, value: browser.librarySection)
    }
}

// MARK: - Secciones (columna izquierda)

private struct SectionRail: View {
    let browser: Browser
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            ForEach(LibrarySection.allCases, id: \.self) { section in
                RailButton(section: section, isSelected: browser.librarySection == section) {
                    browser.librarySection = section
                }
            }
            Spacer()
            HStack {
                Button {
                    withAnimation(Theme.spring) { browser.showsLibrary = false }
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(ChromeButtonStyle(size: 30))
                .tooltip("Volver a la barra lateral", shortcut: "⎋")
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.bottom, 8)
        }
    }

    private struct RailButton: View {
        let section: LibrarySection
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false
        @Environment(\.spaceTheme) private var theme

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .symbolVariant(isSelected ? .fill : .none)
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(Color(theme.title).opacity(isSelected ? 1 : 0.6))
                .frame(width: 80, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(isSelected ? theme.focus : theme.hover))
                        .opacity(isSelected ? 1 : (isHovering ? 0.8 : 0))
                )
                .contentShape(Rectangle())
                .scaleEffect(isHovering && !isSelected ? 1.03 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
            .animation(Theme.spring, value: isSelected)
        }
    }
}

// MARK: - Buscador y filtro

private struct SearchHeader<Trailing: View>: View {
    let placeholder: String
    @Binding var text: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(theme.subtitle))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(theme.hover)))
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Descargas

private struct DownloadsSection: View {
    let downloads: DownloadManager
    @State private var query = ""
    @State private var filter: FileKind = .all
    @Environment(\.spaceTheme) private var theme

    private var visible: [DownloadRecord] {
        downloads.items.filter { record in
            if filter != .all, FileKind.of(record.filename) != filter { return false }
            guard !query.isEmpty else { return true }
            let needle = query.searchNormalized
            return record.filename.searchNormalized.contains(needle)
                || (record.sourceHost ?? "").searchNormalized.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(placeholder: "Buscar en descargas…", text: $query) {
                Menu {
                    Picker("Tipo", selection: $filter) {
                        ForEach(FileKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Abrir la carpeta Descargas") {
                        NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
                    }
                    Button("Vaciar la lista") { downloads.clearList() }
                } label: {
                    Label(filter == .all ? "Filtro" : filter.title, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(theme.hover)))
            }

            if visible.isEmpty {
                EmptyLibraryMessage(
                    symbol: "arrow.down.circle",
                    text: downloads.items.isEmpty ? "Aquí aparecerán los archivos que descargues." : "Sin resultados."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(groups(visible), id: \.0) { day, records in
                            Text(day)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(theme.subtitle).opacity(1.6))
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                            ForEach(records) { record in
                                DownloadRow(downloads: downloads, record: record)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    /// Agrupa por día relativo, conservando el orden (más recientes primero).
    private func groups(_ records: [DownloadRecord]) -> [(String, [DownloadRecord])] {
        var result: [(String, [DownloadRecord])] = []
        for record in records {
            let day = record.relativeDay
            if result.last?.0 == day { result[result.count - 1].1.append(record) } else { result.append((day, [record])) }
        }
        return result
    }
}

struct DownloadRow: View {
    let downloads: DownloadManager
    let record: DownloadRecord
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(record: record, size: 38)
                .opacity(record.fileExists || record.state == .inProgress ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.filename)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(theme.title))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if record.state == .inProgress {
                    ProgressView(value: downloads.progress[record.id] ?? 0)
                        .progressViewStyle(.linear)
                        .tint(Color(theme.accent))
                        .controlSize(.small)
                } else {
                    Text(record.fileExists || record.state != .finished ? record.subtitle : "Archivo eliminado o movido")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if record.state == .inProgress {
                Button { downloads.cancel(record) } label: { Image(systemName: "xmark") }
                    .buttonStyle(ChromeButtonStyle(size: 24))
                    .tooltip("Cancelar descarga")
            } else {
                Menu {
                    Button("Abrir") { downloads.open(record) }.disabled(!record.fileExists)
                    Button("Mostrar en Finder") { downloads.revealInFinder(record) }
                    if let source = record.sourceURL {
                        Button("Copiar enlace de origen") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(source.absoluteString, forType: .string)
                        }
                    }
                    Divider()
                    Button("Quitar de la lista") { withAnimation(Theme.spring) { downloads.removeFromList(record) } }
                    Button("Mover a la papelera", role: .destructive) {
                        withAnimation(Theme.spring) { downloads.moveToTrash(record) }
                    }
                    .disabled(!record.fileExists)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(theme.hover))
                .opacity(isHovering ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
        .onTapGesture(count: 2) { downloads.open(record) }
        .onDrag {
            // Se puede arrastrar el archivo a otra app o al escritorio.
            guard let url = record.fileURL, record.fileExists else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Abrir") { downloads.open(record) }.disabled(!record.fileExists)
            Button("Mostrar en Finder") { downloads.revealInFinder(record) }
            Divider()
            Button("Quitar de la lista") { downloads.removeFromList(record) }
        }
    }
}

// MARK: - Media

private struct MediaSection: View {
    let downloads: DownloadManager
    @State private var query = ""
    @Environment(\.spaceTheme) private var theme

    private var media: [DownloadRecord] {
        downloads.items.filter { record in
            let kind = FileKind.of(record.filename)
            guard (kind == .images || kind == .videos), record.state == .finished, record.fileExists else { return false }
            return query.isEmpty || record.filename.searchNormalized.contains(query.searchNormalized)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(placeholder: "Buscar imágenes y vídeos…", text: $query) { EmptyView() }
            if media.isEmpty {
                EmptyLibraryMessage(symbol: "photo.on.rectangle.angled",
                                    text: "Las imágenes y vídeos que descargues aparecerán aquí.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(media) { record in
                            MediaTile(downloads: downloads, record: record)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private struct MediaTile: View {
        let downloads: DownloadManager
        let record: DownloadRecord
        @State private var isHovering = false

        var body: some View {
            FileThumbnail(record: record, size: 88)
                .frame(height: 88)
                .overlay(alignment: .bottomTrailing) {
                    if FileKind.of(record.filename) == .videos {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(5)
                    }
                }
                .scaleEffect(isHovering ? 1.04 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.25 : 0), radius: 6, y: 3)
                .onHover { hovering in withAnimation(Theme.pressSpring) { isHovering = hovering } }
                .onTapGesture { downloads.open(record) }
                .tooltip(record.filename)
                .contextMenu {
                    Button("Abrir") { downloads.open(record) }
                    Button("Mostrar en Finder") { downloads.revealInFinder(record) }
                }
        }
    }
}

// MARK: - Espacios

private struct SpacesSection: View {
    let browser: Browser
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(browser.spaces) { space in
                    SpaceCard(browser: browser, space: space)
                }
                Button {
                    browser.showsSpaceManager = true
                } label: {
                    Label("Gestionar espacios", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(PillButtonStyle(restingOpacity: 0.6, cornerRadius: 10))
                .foregroundStyle(Color(theme.title))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }

    private struct SpaceCard: View {
        let browser: Browser
        let space: Space
        @State private var isHovering = false

        var body: some View {
            let background = space.theme.background.map { Color($0) }
            Button {
                browser.activate(space)
                withAnimation(Theme.spring) { browser.showsLibrary = false }
            } label: {
                HStack(spacing: 12) {
                    SpaceIcon(space.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(space.name).font(.system(size: 14, weight: .semibold))
                        Text("\(space.allTabs.count) pestañas · \(browser.profileName(space.profileID))")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.7)
                    }
                    Spacer()
                    if space.id == browser.activeSpaceID {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .foregroundStyle(Color(space.theme.title))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: background.count > 1 ? background : background + background,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(GrainOverlay(intensity: space.theme.grain).clipShape(RoundedRectangle(cornerRadius: 14)))
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .scaleEffect(isHovering ? 1.02 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 8 : 3, y: 2)
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(Theme.pressSpring) { isHovering = hovering } }
        }
    }
}

// MARK: - Pestañas archivadas

private struct ArchiveSection: View {
    let browser: Browser
    @State private var query = ""
    @Environment(\.spaceTheme) private var theme

    private var visible: [ArchivedTab] {
        guard !query.isEmpty else { return browser.archive }
        let needle = query.searchNormalized
        return browser.archive.filter {
            $0.title.searchNormalized.contains(needle) || ($0.url.host() ?? "").searchNormalized.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(placeholder: "Buscar pestañas archivadas…", text: $query) {
                Button("Vaciar") { browser.clearArchive() }
                    .buttonStyle(.borderless)
                    .disabled(browser.archive.isEmpty)
            }
            if visible.isEmpty {
                EmptyLibraryMessage(symbol: "archivebox",
                                    text: browser.archive.isEmpty ? "Las pestañas que cierres se guardan aquí." : "Sin resultados.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visible) { archived in
                            ArchivedRow(browser: browser, archived: archived)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private struct ArchivedRow: View {
        let browser: Browser
        let archived: ArchivedTab
        @State private var isHovering = false
        @Environment(\.spaceTheme) private var theme

        var body: some View {
            Button {
                browser.restore(archived)
                withAnimation(Theme.spring) { browser.showsLibrary = false }
            } label: {
                HStack(spacing: 10) {
                    FaviconView(pageURL: archived.url, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(archived.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color(theme.title))
                            .lineLimit(1)
                        Text("\(archived.url.host() ?? "") · \(archived.closedAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                        .opacity(isHovering ? 1 : 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(theme.hover))
                        .opacity(isHovering ? 1 : 0)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering } }
            .tooltip("Restaurar pestaña")
        }
    }
}

private struct EmptyLibraryMessage: View {
    let symbol: String
    let text: String
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color(theme.subtitle).opacity(1.5))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Contraseñas

/// Contraseñas guardadas (las importadas de otros navegadores). Para verlas hay que
/// identificarse con Touch ID o la contraseña del Mac, como en Safari.
private struct PasswordsSection: View {
    let browser: Browser
    let vault: PasswordVault?
    @State private var isUnlocked = false
    @State private var query = ""
    @State private var copiedID: Credential.ID?
    @Environment(\.spaceTheme) private var theme

    private var visible: [Credential] {
        let all = (vault?.credentials ?? []).sorted { $0.host < $1.host }
        guard !query.isEmpty else { return all }
        let needle = query.searchNormalized
        return all.filter { $0.host.searchNormalized.contains(needle) || $0.username.searchNormalized.contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isUnlocked {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.4))
                    Text("Tus contraseñas están protegidas.")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color(theme.title))
                    Button("Desbloquear") { Task { await unlock() } }
                        .controlSize(.large)
                    Button("Importar de otro navegador…") { browser.welcome = .importOnly }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SearchHeader(placeholder: "Buscar contraseñas…", text: $query) {
                    Button("Importar…") { browser.welcome = .importOnly }
                        .buttonStyle(.borderless)
                }
                if visible.isEmpty {
                    EmptyLibraryMessage(symbol: "key",
                                        text: vault?.credentials.isEmpty ?? true
                                            ? "Importa tus contraseñas de Chrome, Arc o Safari y aparecerán aquí."
                                            : "Sin resultados.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(visible) { credential in
                                row(credential)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .onDisappear { isUnlocked = false }
    }

    private func row(_ credential: Credential) -> some View {
        HStack(spacing: 10) {
            FaviconView(pageURL: credential.url, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.host)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(theme.title))
                    .lineLimit(1)
                Text(credential.username.isEmpty ? "Sin usuario" : credential.username)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(credential.password, forType: .string)
                withAnimation(Theme.pressSpring) { copiedID = credential.id }
            } label: {
                Image(systemName: copiedID == credential.id ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ChromeButtonStyle(size: 26))
            .tooltip("Copiar contraseña")
            Button {
                try? vault?.remove(credential)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ChromeButtonStyle(size: 26))
            .tooltip("Eliminar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func unlock() async {
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "ver tus contraseñas guardadas")) ?? false
        guard ok else { return }
        try? vault?.load()
        withAnimation(Theme.spring) { isUnlocked = true }
    }
}
