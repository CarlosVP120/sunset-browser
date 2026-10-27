import AppKit

/// El selector de ⌃Tab de Arc: las pestañas por uso reciente, con una vista previa de cada página.
/// Mientras mantienes ⌃, cada Tab avanza (⇧ retrocede); al soltar ⌃ se abre la resaltada. Un ⌃Tab
/// rápido vuelve a la pestaña anterior sin llegar a mostrar el selector.
public struct TabSwitcher: Equatable {
    /// Las pestañas, de la más reciente (la visible) a la más antigua.
    public var tabIDs: [UUID]
    /// La resaltada.
    public var index: Int
    /// Se muestra tras un instante: un ⌃Tab rápido cambia sin enseñarlo.
    public var isVisible = false
}

extension Browser {
    /// Hasta cuántas pestañas recientes entran en el selector.
    static let tabSwitcherLimit = 10

    /// Las favoritas y las del espacio actual, de la usada más recientemente a la más antigua.
    func recentTabs() -> [BrowserTab] {
        let tabs = favorites + activeSpace.allTabs
        let visibleID = selectedTab?.id
        return tabs.enumerated()
            .sorted { a, b in
                // La visible siempre primero; después por última vez usada (empates: orden de la barra).
                if (a.element.id == visibleID) != (b.element.id == visibleID) { return a.element.id == visibleID }
                if a.element.lastActiveAt != b.element.lastActiveAt { return a.element.lastActiveAt > b.element.lastActiveAt }
                return a.offset < b.offset
            }
            .prefix(Self.tabSwitcherLimit)
            .map(\.element)
    }

    /// ⌃Tab (o ⌃⇧Tab): abre el selector en la pestaña anterior (o la más antigua), o avanza si ya está abierto.
    public func advanceTabSwitcher(backwards: Bool = false) {
        if var switcher = tabSwitcher {
            let count = switcher.tabIDs.count
            switcher.index = (switcher.index + (backwards ? -1 : 1) + count) % count
            tabSwitcher = switcher
            return
        }
        let tabs = recentTabs()
        guard tabs.count > 1 else { return }
        captureVisiblePreview()
        tabSwitcher = TabSwitcher(tabIDs: tabs.map(\.id), index: backwards ? tabs.count - 1 : 1)
    }

    public func showTabSwitcher() {
        tabSwitcher?.isVisible = true
    }

    public func highlightTabSwitcher(_ index: Int) {
        guard let switcher = tabSwitcher, switcher.tabIDs.indices.contains(index) else { return }
        tabSwitcher?.index = index
    }

    /// Soltar ⌃ (o Intro, o un clic): abre la pestaña resaltada.
    public func commitTabSwitcher() {
        guard let switcher = tabSwitcher else { return }
        tabSwitcher = nil
        guard let tab = tab(withID: switcher.tabIDs[switcher.index]) else { return }
        reveal(tab)
    }

    public func cancelTabSwitcher() {
        tabSwitcher = nil
    }

    // MARK: Vistas previas

    /// Captura la pestaña visible un momento después de mostrarse (ya pintada), y cuando termina de cargar.
    func scheduleVisiblePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.captureVisiblePreview()
        }
    }

    func captureVisiblePreview() {
        guard let tab = selectedTab, !tab.isHome, let page = tab.page else { return }
        Task { [weak self] in
            guard let image = await page.snapshot(), let preview = Self.thumbnail(image) else { return }
            self?.tabPreviews[tab.id] = preview
        }
    }

    /// Reducida a 640 px de ancho: suficiente para el selector y sin guardar capturas enormes.
    private static func thumbnail(_ image: NSImage) -> NSImage? {
        let width: CGFloat = 640
        guard image.size.width > 0 else { return nil }
        let size = image.size.width > width
            ? NSSize(width: width, height: image.size.height * width / image.size.width) : image.size
        // Dibujada ya en un mapa de bits pequeño (no guarda la captura original).
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let thumbnail = NSImage(size: size)
        thumbnail.addRepresentation(bitmap)
        return thumbnail
    }
}
