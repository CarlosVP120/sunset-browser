import AppKit
import SwiftUI
import Observation
import BrowserCore
import BrowserUI

/// La lista de la barra lateral (cabecera del espacio, fijadas, carpetas, separador, "Nueva
/// pestaña" y Hoy) como una tabla nativa de AppKit.
///
/// Con SwiftUI, cada fotograma de una animación (abrir una carpeta, mover pestañas) recalculaba
/// la lista entera y en monitores de 120–144 Hz no daba tiempo. Aquí las filas son vistas de
/// AppKit con capas: la tabla anima insertar, quitar y mover filas desplazando capas, sin
/// recalcular nada, como Finder, Mail o Arc.
struct SidebarListView: NSViewRepresentable {
    let browser: Browser
    let space: Space
    let theme: SpaceTheme
    let controller: SidebarListController
    @Environment(SidebarDrag.self) private var drag

    func makeCoordinator() -> SidebarListCoordinator {
        SidebarListCoordinator(browser: browser, space: space, theme: theme)
    }

    func makeNSView(context: Context) -> SidebarScrollView {
        let coordinator = context.coordinator
        let table = SidebarTableView()
        table.coordinator = coordinator
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.focusRingType = .none
        table.usesAutomaticRowHeights = false
        table.draggingDestinationFeedbackStyle = .gap
        table.registerForDraggedTypes([.string, .URL])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .link], forLocal: false)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.action = #selector(SidebarListCoordinator.clicked)
        table.doubleAction = #selector(SidebarListCoordinator.doubleClicked)

        let scroll = SidebarScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        scroll.contentView.postsBoundsChangedNotifications = true

        coordinator.controller = controller
        controller.coordinator = coordinator
        coordinator.attach(table: table, scrollView: scroll, drag: drag)
        coordinator.registerDropResolver()
        return scroll
    }

    func updateNSView(_ view: SidebarScrollView, context: Context) {
        controller.coordinator = context.coordinator
        context.coordinator.controller = controller
        context.coordinator.theme = theme
    }

    static func dismantleNSView(_ view: SidebarScrollView, coordinator: SidebarListCoordinator) {
        coordinator.detach()
    }
}

/// Lo que SwiftUI le pide a la lista desde fuera: volver arriba, saber si hay scroll y dónde está.
@MainActor
final class SidebarListController {
    weak var coordinator: SidebarListCoordinator?
    var onScrollChange: ((Bool) -> Void)?
    /// Marco de la lista en el espacio de arrastre de la barra lateral.
    var frame: CGRect = .zero {
        didSet { if frame != oldValue { coordinator?.registerDropResolver() } }
    }

    func scrollToTop() { coordinator?.scrollToTop() }
}

// MARK: - Vistas de AppKit

final class SidebarScrollView: NSScrollView {
    private let fadeMask = CAGradientLayer()
    var fadesTop = false {
        didSet {
            guard fadesTop != oldValue else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            updateMask()
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.mask = fadeMask
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        updateMask()
        CATransaction.commit()
    }

    /// Al hacer scroll, el contenido se funde bajo los favoritos (14 pt) en vez de cortarse.
    private func updateMask() {
        let fade = 14 / max(bounds.height, 1)
        // La capa no está volteada: y = 0 es abajo, así que el desvanecido va al final.
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                           NSColor.black.withAlphaComponent(fadesTop ? 0 : 1).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - fade)), 1]
    }
}

final class SidebarTableView: NSTableView {
    weak var coordinator: SidebarListCoordinator?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        coordinator?.setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        coordinator?.setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        coordinator?.setHoveredRow(-1)
    }

    /// Los botones, campos de texto y la cabecera (SwiftUI) reciben sus clics; el resto de la fila
    /// lo gestiona la tabla (clic para abrir, arrastrar para mover).
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSButton || (responder as? NSTextField)?.isEditable == true || responder is NSTextView { return true }
        if let view = responder as? NSView, coordinator?.isInHeader(view) == true { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return coordinator?.menu(forRow: row)
    }

    // La tabla no se queda con el foco del teclado (no hay selección propia).
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - Coordinador

@MainActor
final class SidebarListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Kind {
        case header
        case pinnedTab(BrowserTab, Int)
        case folder(Folder, Int)
        case folderTab(BrowserTab, Folder, Int)
        case separator
        case newTab
        case todayTab(BrowserTab, Int)
    }

    struct Row {
        let id: String
        let kind: Kind

        var tab: BrowserTab? {
            switch kind {
            case .pinnedTab(let tab, _), .folderTab(let tab, _, _), .todayTab(let tab, _): tab
            default: nil
            }
        }
    }

    let browser: Browser
    let space: Space
    var theme: SpaceTheme {
        didSet {
            guard theme != oldValue else { return }
            colors = SidebarColors(theme)
            headerHost?.rootView = headerRoot
            reconfigureVisibleRows()
        }
    }
    private(set) var colors: SidebarColors
    private weak var table: SidebarTableView?
    private weak var scrollView: SidebarScrollView?
    private weak var drag: SidebarDrag?
    private var rows: [Row] = []
    private var hoveredRow = -1
    private var renamingFolderID: UUID?
    private var headerHost: NSHostingView<AnyView>?
    private var isObserving = false
    private var isScrolled = false
    private let resolverID = UUID()
    private var dropLine = CALayer()
    private var dropHighlightRow = -1
    private var previewPopover: NSPopover?
    /// Durante un arrastre nativo (y justo después) la tabla mueve filas por su cuenta para abrir
    /// el hueco: los cambios de ese momento se pintan sin animar, o las dos animaciones chocan.
    private var isNativeDragging = false
    private var lastNativeDragEnd = Date.distantPast
    private var previewTask: Task<Void, Never>?
    /// Como en Arc: al hacer clic en una carpeta su vista previa no vuelve a salir hasta que el
    /// ratón sale de ella y vuelve a entrar.
    private var previewSuppressedFolderID: UUID?
    weak var controller: SidebarListController?

    init(browser: Browser, space: Space, theme: SpaceTheme) {
        self.browser = browser
        self.space = space
        self.theme = theme
        colors = SidebarColors(theme)
        super.init()
    }

    func attach(table: SidebarTableView, scrollView: SidebarScrollView, drag: SidebarDrag) {
        self.table = table
        self.scrollView = scrollView
        self.drag = drag
        rows = buildRows()
        table.reloadData()
        dropLine.backgroundColor = colors.accent.cgColor
        dropLine.cornerRadius = 1.25
        dropLine.opacity = 0
        table.wantsLayer = true
        table.layer?.addSublayer(dropLine)
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        isObserving = true
        observe()
    }

    func detach() {
        isObserving = false
        NotificationCenter.default.removeObserver(self)
        drag?.unregisterResolver(resolverID)
        previewPopover?.close()
    }

    // MARK: Filas

    private func buildRows() -> [Row] {
        var result = [Row(id: "header", kind: .header)]
        if !space.isPinnedCollapsed {
            for (index, item) in space.pinned.enumerated() {
                switch item {
                case .tab(let tab):
                    result.append(Row(id: "tab-\(tab.id)", kind: .pinnedTab(tab, index)))
                case .folder(let folder):
                    result.append(Row(id: "folder-\(folder.id)", kind: .folder(folder, index)))
                    if folder.isExpanded {
                        for (childIndex, tab) in folder.tabs.enumerated() {
                            result.append(Row(id: "tab-\(tab.id)", kind: .folderTab(tab, folder, childIndex)))
                        }
                    }
                }
            }
        }
        result.append(Row(id: "separator", kind: .separator))
        result.append(Row(id: "new-tab", kind: .newTab))
        for (index, tab) in space.tabs.enumerated() {
            result.append(Row(id: "tab-\(tab.id)", kind: .todayTab(tab, index)))
        }
        return result
    }

    /// Se suscribe a todo lo que se ve en la lista; cualquier cambio vuelve a pintar (agrupado
    /// en el siguiente ciclo).
    private func observe() {
        guard isObserving else { return }
        withObservationTracking {
            let rows = buildRows()
            _ = browser.selectedTab?.id
            _ = browser.renamingTabID
            _ = space.tabs.isEmpty
            for row in rows {
                if let tab = row.tab {
                    _ = (tab.displayTitle, tab.url, tab.faviconURL, tab.isLoading, tab.progress, tab.isHibernated,
                         tab.isAwayFromPinned, tab.isDeveloperMode, tab.isHome)
                    if let key = FaviconCache.key(for: tab.url) { _ = FaviconCache.shared.image(for: key) }
                } else if case .folder(let folder, _) = row.kind {
                    _ = (folder.name, folder.isExpanded)
                }
            }
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isObserving else { return }
                    self.refresh()
                    self.observe()
                }
            }
        }
    }

    private func refresh() {
        guard let table else { return }
        let newRows = buildRows()
        let oldIDs = rows.map(\.id), newIDs = newRows.map(\.id)
        let oldHeights = Dictionary(rows.map { ($0.id, height(of: $0)) }, uniquingKeysWith: { first, _ in first })
        let afterDrag = isNativeDragging || Date().timeIntervalSince(lastNativeDragEnd) < 0.6
        if oldIDs != newIDs, afterDrag {
            hoveredRow = -1
            rows = newRows
            table.reloadData()
        } else if oldIDs != newIDs {
            let difference = newIDs.difference(from: oldIDs)
            var removals = IndexSet(), insertions = IndexSet()
            var onlyFolderRows = true
            for change in difference {
                switch change {
                case .remove(let offset, _, _):
                    removals.insert(offset)
                    if case .folderTab = rows[offset].kind {} else { onlyFolderRows = false }
                case .insert(let offset, _, _):
                    insertions.insert(offset)
                    if case .folderTab = newRows[offset].kind {} else { onlyFolderRows = false }
                }
            }
            hoveredRow = -1
            rows = newRows
            // Abrir/cerrar una carpeta: las filas se deslizan desde/hacia la carpeta.
            let insertAnimation: NSTableView.AnimationOptions = onlyFolderRows ? [.slideDown, .effectFade] : [.effectFade, .slideDown]
            let removeAnimation: NSTableView.AnimationOptions = onlyFolderRows ? [.slideUp, .effectFade] : [.effectFade, .slideUp]
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
                table.beginUpdates()
                table.removeRows(at: removals, withAnimation: removeAnimation)
                table.insertRows(at: insertions, withAnimation: insertAnimation)
                table.endUpdates()
            }
        } else {
            rows = newRows
        }
        let changedHeights = IndexSet(rows.indices.filter { index in
            guard let old = oldHeights[rows[index].id] else { return false }
            return old != height(of: rows[index])
        })
        if !changedHeights.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                table.noteHeightOfRows(withIndexesChanged: changedHeights)
            }
        }
        // La fila bajo el ratón sigue resaltada tras el cambio (sin esperar a que se mueva).
        if let window = table.window {
            let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            hoveredRow = table.visibleRect.contains(point) ? table.row(at: point) : -1
        }
        reconfigureVisibleRows()
    }

    private func height(of row: Row) -> CGFloat {
        switch row.kind {
        case .header: 30
        case .separator: 18
        case .folder, .newTab: Theme.rowHeight
        case .pinnedTab(let tab, _), .folderTab(let tab, _, _), .todayTab(let tab, _): tab.isDeveloperMode ? 44 : Theme.rowHeight
        }
    }

    private func reconfigureVisibleRows() {
        guard let table else { return }
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<min(visible.location + visible.length, rows.count) {
            if let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) {
                configure(view, row: row)
            }
            if let rowView = table.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
                configure(rowView, row: row)
            }
        }
    }

    // MARK: Tabla

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows.indices.contains(row) ? height(of: rows[row]) : Theme.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = tableView.makeView(withIdentifier: id, owner: nil) as? SidebarRowView ?? {
            let view = SidebarRowView()
            view.identifier = id
            return view
        }()
        configure(view, row: row)
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let view: NSView
        switch rows[row].kind {
        case .header:
            view = header()
        case .pinnedTab, .folderTab, .todayTab:
            view = reuse(tableView, "tab") { TabCellView() }
        case .folder:
            view = reuse(tableView, "folder") { FolderCellView() }
        case .separator:
            view = reuse(tableView, "separator") { SeparatorCellView() }
        case .newTab:
            view = reuse(tableView, "new-tab") { NewTabCellView() }
        }
        configure(view, row: row)
        return view
    }

    private func reuse<V: NSView>(_ tableView: NSTableView, _ id: String, make: () -> V) -> V {
        let identifier = NSUserInterfaceItemIdentifier(id)
        if let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? V { return view }
        let view = make()
        view.identifier = identifier
        return view
    }

    private func configure(_ view: NSView, row: Int) {
        guard rows.indices.contains(row) else { return }
        let item = rows[row]
        let isHovered = row == hoveredRow
        switch item.kind {
        case .header:
            break
        case .pinnedTab(let tab, _), .todayTab(let tab, _):
            configureTab(view, tab: tab, indent: 0, isHovered: isHovered)
        case .folderTab(let tab, _, _):
            configureTab(view, tab: tab, indent: 14, isHovered: isHovered)
        case .folder(let folder, _):
            guard let cell = view as? FolderCellView else { return }
            cell.coordinator = self
            cell.configure(folder: folder, isRenaming: renamingFolderID == folder.id, colors: colors)
        case .separator:
            guard let cell = view as? SeparatorCellView else { return }
            cell.coordinator = self
            cell.configure(isHovered: isHovered, hasTodayTabs: !space.tabs.isEmpty, colors: colors)
        case .newTab:
            (view as? NewTabCellView)?.configure(colors: colors)
        }
    }

    private func configureTab(_ view: NSView, tab: BrowserTab, indent: CGFloat, isHovered: Bool) {
        guard let cell = view as? TabCellView else { return }
        cell.coordinator = self
        cell.configure(tab: tab, indent: indent, isSelected: browser.selectedTab?.id == tab.id,
                       isPinned: space.isPinned(tab), isHovered: isHovered,
                       isRenaming: browser.renamingTabID == tab.id, colors: colors)
    }

    private func configure(_ rowView: SidebarRowView, row: Int) {
        guard rows.indices.contains(row) else { return }
        let item = rows[row]
        rowView.colors = colors
        switch item.kind {
        case .header, .separator: rowView.isHoverable = false
        default: rowView.isHoverable = true
        }
        rowView.isHovered = row == hoveredRow || row == dropHighlightRow
        rowView.isActive = item.tab.map { $0.id == browser.selectedTab?.id } ?? false
        rowView.showsDeveloperBorder = item.tab?.isDeveloperMode ?? false
    }

    // MARK: Cabecera (SwiftUI)

    private var headerRoot: AnyView {
        AnyView(SpaceHeader(browser: browser, space: space, inList: true)
            .environment(\.spaceTheme, theme)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .environment(\.tooltipOrigin, TooltipOrigin { [weak self] in self?.headerOrigin() ?? .zero })
            .padding(.trailing, 0))
    }

    private func header() -> NSView {
        if let headerHost { return headerHost }
        let host = NSHostingView(rootView: headerRoot)
        host.sizingOptions = []
        headerHost = host
        return host
    }

    /// Dónde está la cabecera en la ventana (para colocar sus tooltips).
    private func headerOrigin() -> CGPoint {
        guard let host = headerHost, let contentView = host.window?.contentView else { return .zero }
        let rect = host.convert(host.bounds, to: contentView)
        return CGPoint(x: rect.minX, y: contentView.isFlipped ? rect.minY : contentView.bounds.height - rect.maxY)
    }

    func isInHeader(_ view: NSView) -> Bool {
        guard let headerHost else { return false }
        return view === headerHost || view.isDescendant(of: headerHost)
    }

    // MARK: Ratón

    func setHoveredRow(_ row: Int) {
        guard row != hoveredRow, let table else { return }
        let old = hoveredRow
        hoveredRow = row
        for index in [old, row] where rows.indices.contains(index) {
            if let view = table.view(atColumn: 0, row: index, makeIfNecessary: false) { configure(view, row: index) }
            if let rowView = table.rowView(atRow: index, makeIfNecessary: false) as? SidebarRowView { configure(rowView, row: index) }
        }
        updatePreview()
    }

    @objc func clicked() {
        guard let table, rows.indices.contains(table.clickedRow) else { return }
        switch rows[table.clickedRow].kind {
        case .pinnedTab(let tab, _), .folderTab(let tab, _, _), .todayTab(let tab, _):
            browser.select(tab)
        case .folder(let folder, _):
            closePreview()
            previewSuppressedFolderID = folder.id
            browser.toggle(folder)
        case .newTab:
            browser.openHome()
        default:
            break
        }
    }

    @objc func doubleClicked() {
        guard let table, rows.indices.contains(table.clickedRow) else { return }
        // La tabla manda el segundo clic rápido solo como doble clic: en una carpeta cuenta como
        // otro clic (abrir y cerrar seguido), en una pestaña la renombra.
        if case .folder = rows[table.clickedRow].kind { return clicked() }
        guard let tab = rows[table.clickedRow].tab else { return }
        browser.renamingTabID = tab.id
    }

    func menu(forRow row: Int) -> NSMenu? {
        guard rows.indices.contains(row) else { return nil }
        let entries: [MenuEntry]
        switch rows[row].kind {
        case .header:
            entries = SpaceMenu.entries(browser: browser, space: space)
        case .pinnedTab(let tab, _), .folderTab(let tab, _, _), .todayTab(let tab, _):
            entries = SidebarMenus.tab(tab, browser: browser)
        case .folder(let folder, _):
            entries = SidebarMenus.folder(folder, browser: browser) { [weak self] in
                self?.renamingFolderID = folder.id
                self?.reconfigureVisibleRows()
            }
        default:
            return nil
        }
        return NSMenu.build(entries)
    }

    func finishRenaming(_ folder: Folder?, to name: String) {
        if let folder { browser.rename(folder, to: name) }
        renamingFolderID = nil
        reconfigureVisibleRows()
    }

    // MARK: Vista previa de carpeta (como en Arc)

    private func updatePreview() {
        previewTask?.cancel()
        let folder: Folder? = rows.indices.contains(hoveredRow) ? {
            if case .folder(let folder, _) = rows[hoveredRow].kind { return folder }
            return nil
        }() : nil
        if folder?.id != previewSuppressedFolderID { previewSuppressedFolderID = nil }
        if let folder, !folder.tabs.isEmpty, folder.id != previewSuppressedFolderID,
           drag?.isDragging != true, renamingFolderID == nil {
            let row = hoveredRow
            previewTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                self?.showPreview(folder, row: row)
            }
        } else if previewPopover?.isShown == true {
            previewTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                // Si el ratón está dentro de la vista previa, se queda abierta.
                if let window = previewPopover?.contentViewController?.view.window,
                   window.frame.contains(NSEvent.mouseLocation) { return }
                closePreview()
            }
        }
    }

    private func showPreview(_ folder: Folder, row: Int) {
        guard let table, rows.indices.contains(row), previewPopover?.isShown != true else { return }
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: FolderPreview(browser: browser, folder: folder) { [weak self] in
            self?.closePreview()
        }
        .environment(\.spaceTheme, theme)
        .onHover { [weak self] inside in if !inside { self?.updatePreview() } })
        popover.show(relativeTo: table.rect(ofRow: row), of: table, preferredEdge: .maxX)
        previewPopover = popover
    }

    private func closePreview() {
        previewTask?.cancel()
        previewPopover?.close()
        previewPopover = nil
    }

    // MARK: Scroll

    @objc private func scrolled() {
        guard let scrollView else { return }
        let scrolled = scrollView.contentView.bounds.minY > 60
        scrollView.fadesTop = scrollView.contentView.bounds.minY > 2
        if scrolled != isScrolled {
            isScrolled = scrolled
            controller?.onScrollChange?(scrolled)
        }
        closePreview()
    }

    func scrollToTop() {
        guard let scrollView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.allowsImplicitAnimation = true
            scrollView.contentView.animator().setBoundsOrigin(.zero)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Arrastrar (AppKit)

    private enum Target {
        case tab(DropLocation)
        case folder(Int)
    }

    /// Dónde cae algo soltado justo encima de la fila `row` (o dentro, si es una carpeta).
    private func target(before row: Int, inside: Bool, payload: DragPayload) -> Target? {
        let isFolderPayload: Bool = { if case .folder = payload { return true } else { return false } }()
        if inside, rows.indices.contains(row), case .folder(let folder, _) = rows[row].kind {
            if case .folder(let id) = payload, id == folder.id { return nil }
            return isFolderPayload ? nil : .tab(.folder(folder, folder.tabs.count))
        }
        guard rows.indices.contains(row) else {
            return isFolderPayload ? nil : .tab(.today(space.tabs.count))
        }
        switch rows[row].kind {
        case .header:
            return isFolderPayload ? .folder(0) : .tab(.pinned(0))
        case .pinnedTab(_, let index), .folder(_, let index):
            return isFolderPayload ? .folder(index) : .tab(.pinned(index))
        case .folderTab(_, let folder, let index):
            return isFolderPayload ? nil : .tab(.folder(folder, index))
        case .separator:
            return isFolderPayload ? .folder(space.pinned.count) : .tab(.pinned(space.pinned.count))
        case .newTab:
            return isFolderPayload ? .folder(space.pinned.count) : .tab(.today(0))
        case .todayTab(_, let index):
            return isFolderPayload ? nil : .tab(.today(index))
        }
    }

    private func perform(_ target: Target, payload: DragPayload) {
        switch (target, payload) {
        case (.tab(let location), .tab(let id)):
            if let tab = browser.tab(withID: id) { browser.move(tab, to: location) }
        case (.tab(let location), .url(let url)):
            browser.open(url, at: location)
        case (.folder(let index), .folder(let id)):
            if let folder = browser.folder(withID: id) { browser.move(folder, toPinnedIndex: index) }
        default:
            break
        }
    }

    private func payload(from pasteboard: NSPasteboard) -> DragPayload? {
        if let string = pasteboard.string(forType: .string), let payload = DragPayload.parse(string) { return payload }
        if let url = NSURL(from: pasteboard) as URL?, url.scheme == "http" || url.scheme == "https" { return .url(url) }
        return nil
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard rows.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        switch rows[row].kind {
        case .pinnedTab(let tab, _), .folderTab(let tab, _, _), .todayTab(let tab, _):
            item.setString("minavegador-tab:\(tab.id.uuidString)", forType: .string)
            if let url = tab.url { item.setString(url.absoluteString, forType: .URL) }
        case .folder(let folder, _):
            item.setString("minavegador-folder:\(folder.id.uuidString)", forType: .string)
        default:
            return nil
        }
        return item
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        closePreview()
        isNativeDragging = true
        drag?.isNativeDragActive = true
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        isNativeDragging = false
        lastNativeDragEnd = Date()
        drag?.isNativeDragActive = false
        // Si se soltó fuera de la lista (favoritos, otro espacio…), se repinta limpia.
        DispatchQueue.main.async { [weak self] in self?.table?.reloadData() }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard let payload = payload(from: info.draggingPasteboard) else { return [] }
        let inside = operation == .on
        if inside, target(before: row, inside: true, payload: payload) == nil {
            // Sobre una fila que no acepta cosas dentro: se suelta encima de ella.
            tableView.setDropRow(row, dropOperation: .above)
            return target(before: row, inside: false, payload: payload) == nil ? [] : .move
        }
        guard target(before: row, inside: inside, payload: payload) != nil else { return [] }
        if case .url = payload { return .copy }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let payload = payload(from: info.draggingPasteboard),
              let target = target(before: row, inside: dropOperation == .on, payload: payload) else { return false }
        perform(target, payload: payload)
        return true
    }

    // MARK: Arrastrar desde SwiftUI (favoritos e iconos de espacios)

    func registerDropResolver() {
        guard let drag, let controller else { return }
        drag.register(resolverID, resolver: .init(
            frame: controller.frame,
            resolve: { [weak self] payload, point in self?.resolve(payload, at: point) },
            indicate: { [weak self] point, payload in self?.indicate(point, payload: payload) }
        ))
    }

    /// Fila y modo (encima o dentro) bajo un punto de la lista (origen arriba a la izquierda).
    private func dropPosition(at point: CGPoint) -> (row: Int, inside: Bool)? {
        guard let table, let scrollView else { return nil }
        let tablePoint = CGPoint(x: 20, y: point.y + scrollView.contentView.bounds.minY)
        let row = table.row(at: tablePoint)
        guard row >= 0 else { return (rows.count, false) }
        let rect = table.rect(ofRow: row)
        let fraction = (tablePoint.y - rect.minY) / max(rect.height, 1)
        if case .folder = rows[row].kind, fraction > 0.28, fraction < 0.72 { return (row, true) }
        return (fraction < 0.5 ? row : row + 1, false)
    }

    private func resolve(_ payload: DragPayload, at point: CGPoint) -> (@MainActor () -> Void)? {
        guard let position = dropPosition(at: point),
              let target = target(before: position.row, inside: position.inside, payload: payload) else { return nil }
        return { [weak self] in self?.perform(target, payload: payload) }
    }

    private func indicate(_ point: CGPoint?, payload: DragPayload?) {
        guard let table else { return }
        let oldHighlight = dropHighlightRow
        dropHighlightRow = -1
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        if let point, let payload, let position = dropPosition(at: point),
           target(before: position.row, inside: position.inside, payload: payload) != nil {
            if position.inside {
                dropHighlightRow = position.row
                dropLine.opacity = 0
            } else {
                let y = position.row < rows.count ? table.rect(ofRow: position.row).minY - 1 : table.rect(ofRow: rows.count - 1).maxY + 1
                dropLine.backgroundColor = colors.accent.cgColor
                dropLine.frame = CGRect(x: 6, y: y - 1.25, width: table.bounds.width - 12, height: 2.5)
                dropLine.opacity = 1
            }
        } else {
            dropLine.opacity = 0
        }
        CATransaction.commit()
        for index in [oldHighlight, dropHighlightRow] where rows.indices.contains(index) {
            if let rowView = table.rowView(atRow: index, makeIfNecessary: false) as? SidebarRowView { configure(rowView, row: index) }
        }
    }
}
