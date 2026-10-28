import AppKit
import QuartzCore
import BrowserCore
import BrowserUI

// Filas de la lista nativa de la barra lateral. Son vistas de AppKit con capas de Core
// Animation: al abrir una carpeta o mover pestañas, la tabla las desplaza como capas, sin
// recalcular nada (lo que hacen Finder, Mail o Arc).

/// Colores del tema, ya convertidos para AppKit.
struct SidebarColors {
    let title: NSColor
    let subtitle: NSColor
    let hover: NSColor
    let focus: NSColor
    let accent: NSColor
    let isDark: Bool

    init(_ theme: SpaceTheme) {
        title = NSColor(theme.title)
        subtitle = NSColor(theme.subtitle)
        hover = NSColor(theme.hover)
        focus = NSColor(theme.focus)
        accent = NSColor(theme.accent)
        isDark = theme.isDark
    }

    static let developer = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.22, alpha: 0.9)
}

// MARK: - Fondo de fila

/// Fondo de cada fila: hover, pestaña seleccionada (con su filo de luz y sombra) y el borde
/// punteado del modo desarrollador.
final class SidebarRowView: NSTableRowView {
    var colors: SidebarColors? { didSet { updateLayers(animated: false) } }
    var isHoverable = true
    var isHovered = false { didSet { if isHovered != oldValue { updateLayers(animated: true) } } }
    var isActive = false { didSet { if isActive != oldValue { updateLayers(animated: true) } } }
    var showsDeveloperBorder = false { didSet { if showsDeveloperBorder != oldValue { updateLayers(animated: true) } } }

    private let hoverLayer = CALayer()
    private let activeLayer = CALayer()
    private let shineLayer = CAGradientLayer()
    private let shineMask = CAShapeLayer()
    private let developerLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for sublayer in [hoverLayer, activeLayer] {
            sublayer.cornerRadius = Theme.cornerRadius
            sublayer.cornerCurve = .continuous
            sublayer.opacity = 0
            layer?.addSublayer(sublayer)
        }
        activeLayer.shadowColor = NSColor.black.cgColor
        activeLayer.shadowOpacity = 0.18
        activeLayer.shadowRadius = 2
        activeLayer.shadowOffset = CGSize(width: 0, height: -1)
        shineLayer.colors = [NSColor.white.withAlphaComponent(0.14).cgColor, NSColor.clear.cgColor]
        shineLayer.startPoint = CGPoint(x: 0.5, y: 0)
        shineLayer.endPoint = CGPoint(x: 0.5, y: 1)
        shineMask.fillColor = nil
        shineMask.strokeColor = NSColor.black.cgColor
        shineMask.lineWidth = 1
        shineLayer.mask = shineMask
        activeLayer.addSublayer(shineLayer)
        developerLayer.fillColor = nil
        developerLayer.strokeColor = SidebarColors.developer.cgColor
        developerLayer.lineWidth = 1.6
        developerLayer.lineDashPattern = [4.5, 3.5]
        developerLayer.opacity = 0
        layer?.addSublayer(developerLayer)
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override var isFlipped: Bool { true }
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // La fila incluye la separación con la siguiente (`intercellSpacing`): el fondo la deja libre
        // para que, con hover o seleccionadas, las pestañas no se vean pegadas.
        let gap = (superview as? NSTableView)?.intercellSpacing.height ?? 0
        let pill = bounds.insetBy(dx: 0, dy: gap / 2)
        hoverLayer.frame = pill
        activeLayer.frame = pill
        shineLayer.frame = activeLayer.bounds
        shineMask.frame = shineLayer.bounds
        shineMask.path = CGPath(roundedRect: activeLayer.bounds.insetBy(dx: 0.5, dy: 0.5),
                                cornerWidth: Theme.cornerRadius, cornerHeight: Theme.cornerRadius, transform: nil)
        let border = pill.insetBy(dx: -1, dy: -1)
        developerLayer.frame = bounds
        developerLayer.path = CGPath(roundedRect: border.insetBy(dx: 0.8, dy: 0.8),
                                     cornerWidth: Theme.cornerRadius + 2, cornerHeight: Theme.cornerRadius + 2, transform: nil)
        CATransaction.commit()
    }

    private func updateLayers(animated: Bool) {
        guard let colors else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? (isHovered ? 0.08 : 0.22) : 0)
        CATransaction.setDisableActions(!animated)
        hoverLayer.backgroundColor = colors.hover.cgColor
        activeLayer.backgroundColor = colors.focus.cgColor
        hoverLayer.opacity = isHoverable && isHovered && !isActive ? 1 : 0
        activeLayer.opacity = isActive ? 1 : 0
        developerLayer.opacity = showsDeveloperBorder ? 1 : 0
        CATransaction.commit()
    }
}

// MARK: - Piezas comunes

/// Botón pequeño con fondo al pasar el ratón (como `ChromeButtonStyle`) y tooltip.
final class HoverButton: NSButton {
    var tooltipText: String?
    var tooltipShortcut: String?
    var hoverColor: NSColor = .clear { didSet { if isHovered { layer?.backgroundColor = hoverColor.cgColor } } }
    private var isHovered = false
    private let tooltipID = UUID()
    private var tracking: NSTrackingArea?

    convenience init(symbol: String, size: CGFloat, weight: NSFont.Weight = .bold, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        setSymbol(symbol, size: size, weight: weight)
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        focusRingType = .none
    }

    func setSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .bold) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = hoverColor.cgColor
        if let tooltipText { Tooltips.show(tooltipText, shortcut: tooltipShortcut, for: self, owner: tooltipID) }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = nil
        Tooltips.hide(owner: tooltipID)
    }

    override func mouseDown(with event: NSEvent) {
        Tooltips.hide(owner: tooltipID)
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Tooltips.hide(owner: tooltipID) }
    }
}

/// Etiqueta de una línea que se desvanece al final (como `FadingText`), con un hueco opcional
/// al final (bajo el botón de cerrar).
final class FadingLabel: NSView {
    let field = NSTextField(labelWithString: "")
    private let fadeMask = CAGradientLayer()
    var fade: CGFloat = 14 { didSet { needsLayout = true } }
    var trailingClear: CGFloat = 0 {
        didSet {
            guard trailingClear != oldValue else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            updateMask()
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = false
        addSubview(field)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor]
        layer?.mask = fadeMask
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override func layout() {
        super.layout()
        let height = field.intrinsicContentSize.height
        field.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: max(bounds.width, field.intrinsicContentSize.width + 4), height: height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        updateMask()
        CATransaction.commit()
    }

    private func updateMask() {
        let width = max(bounds.width, 1)
        let end = max(0, (width - trailingClear) / width)
        let start = max(0, end - fade / width)
        fadeMask.locations = [0, NSNumber(value: Double(start)), NSNumber(value: Double(end)), 1]
    }
}

// MARK: - Pestaña

final class TabCellView: NSView, NSTextFieldDelegate {
    weak var coordinator: SidebarListCoordinator?
    private(set) var tab: BrowserTab?

    private let favicon = NSImageView()
    private let faviconBox = NSView()
    private let ringTrack = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let slashButton = NSButton(title: "/", target: nil, action: nil)
    private let title = FadingLabel()
    private let subtitle = FadingLabel()
    private var removesPinned = false
    private let closeButton = HoverButton(symbol: "xmark", size: 9.5, target: nil, action: nil)
    private let renameField = NSTextField()
    private var indent: CGFloat = 0
    private var isRenaming = false
    private var isHovered = false
    private var requestedIcon: String?
    private var wasLoading = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        faviconBox.wantsLayer = true
        favicon.imageScaling = .scaleProportionallyUpOrDown
        favicon.wantsLayer = true
        favicon.layer?.cornerRadius = 3.5
        favicon.layer?.cornerCurve = .continuous
        favicon.layer?.masksToBounds = true
        faviconBox.addSubview(favicon)
        for shape in [ringTrack, ring] {
            shape.fillColor = nil
            shape.lineWidth = 1.6
            shape.lineCap = .round
            shape.opacity = 0
            faviconBox.layer?.addSublayer(shape)
        }
        ring.strokeEnd = 0.08
        ring.shadowOpacity = 0.6
        ring.shadowRadius = 2
        ring.shadowOffset = .zero
        addSubview(faviconBox)

        slashButton.isBordered = false
        slashButton.font = .systemFont(ofSize: 15, weight: .light)
        slashButton.target = self
        slashButton.action = #selector(returnToPinned)
        slashButton.isHidden = true
        addSubview(slashButton)

        addSubview(title)
        subtitle.field.font = .systemFont(ofSize: 11, weight: .medium)
        subtitle.isHidden = true
        addSubview(subtitle)

        closeButton.target = self
        closeButton.action = #selector(closeTab)
        closeButton.alphaValue = 0
        addSubview(closeButton)

        renameField.isBordered = false
        renameField.drawsBackground = false
        renameField.focusRingType = .none
        renameField.font = .systemFont(ofSize: 13, weight: .medium)
        renameField.delegate = self
        renameField.isHidden = true
        addSubview(renameField)
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override var isFlipped: Bool { true }

    func configure(tab: BrowserTab, indent: CGFloat, isSelected: Bool, isPinned: Bool, isHovered: Bool,
                   isRenaming: Bool, colors: SidebarColors) {
        let tabChanged = self.tab !== tab
        self.tab = tab
        self.indent = indent
        self.isHovered = isHovered

        // Icono (desde la caché compartida; si falta, se pide).
        if tab.isHome {
            favicon.image = symbol("house.fill", tint: colors.subtitle)
        } else if let key = FaviconCache.key(for: tab.url), let image = FaviconCache.shared.image(for: key) {
            favicon.image = image
        } else {
            favicon.image = symbol("globe", tint: colors.subtitle)
        }
        // También al terminar de cargar: si antes falló (sitio con contraseña aún sin iniciar
        // sesión), se vuelve a intentar; si ya está en la caché no se descarga nada.
        let iconRequest = "\(FaviconCache.key(for: tab.url) ?? "")|\(tab.faviconURL?.absoluteString ?? "")|\(tab.isLoading)"
        if iconRequest != requestedIcon, !tab.isHome {
            requestedIcon = iconRequest
            let pageURL = tab.url, iconURL = tab.faviconURL
            Task { await FaviconCache.shared.load(pageURL: pageURL, iconURL: iconURL) }
        }

        // Anillo de carga alrededor del icono.
        CATransaction.begin()
        CATransaction.setAnimationDuration(tabChanged ? 0 : 0.25)
        CATransaction.setDisableActions(tabChanged)
        ringTrack.strokeColor = colors.title.withAlphaComponent(0.15).cgColor
        ring.strokeColor = colors.accent.cgColor
        ring.shadowColor = colors.accent.cgColor
        ring.opacity = tab.isLoading ? 1 : 0
        ringTrack.opacity = tab.isLoading ? 1 : 0
        ring.strokeEnd = max(0.08, tab.progress)
        // Las capas de AppKit escalan desde la esquina (anchorPoint 0,0): se escala alrededor del
        // centro para que el icono quede centrado dentro del anillo.
        let center: CGFloat = 8
        favicon.layer?.setAffineTransform(tab.isLoading
            ? CGAffineTransform(translationX: center, y: center).scaledBy(x: 0.78, y: 0.78).translatedBy(x: -center, y: -center)
            : .identity)
        CATransaction.commit()
        wasLoading = tab.isLoading

        // Título.
        title.field.stringValue = tab.displayTitle
        title.field.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        title.field.textColor = colors.title.withAlphaComponent(tab.isHibernated && !isSelected ? 0.72 : 1)
        title.trailingClear = isHovered ? 24 : 0

        // "/": la fijada se movió de su dirección (pulsarla la devuelve).
        slashButton.isHidden = !tab.isAwayFromPinned
        slashButton.contentTintColor = colors.subtitle
        slashButton.attributedTitle = NSAttributedString(string: "/", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .light), .foregroundColor: colors.subtitle,
        ])
        slashButton.toolTip = "Volver a \(tab.pinnedURL?.host() ?? "la dirección fijada")"

        // Modo desarrollador: el servidor bajo el título.
        subtitle.isHidden = !tab.isDeveloperMode
        subtitle.field.stringValue = DeveloperMode.hostAndPort(tab.url)
        subtitle.field.textColor = colors.subtitle
        subtitle.trailingClear = isHovered ? 24 : 0

        // Cerrar (o descargar, si es fijada). Una fijada ya cerrada muestra × para quitarla, como Arc.
        removesPinned = isPinned && tab.isHibernated && !tab.isAwayFromPinned
        closeButton.setSymbol(isPinned && !removesPinned ? "minus" : "xmark", size: 9.5)
        closeButton.contentTintColor = colors.title.withAlphaComponent(0.85)
        closeButton.hoverColor = colors.hover
        closeButton.tooltipText = removesPinned ? "Quitar de fijadas"
            : isPinned ? (tab.isAwayFromPinned ? "Volver a la dirección fijada" : "Descargar de memoria") : "Cerrar pestaña"
        closeButton.tooltipShortcut = removesPinned ? nil : "⌘W"
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isHovered ? 0.08 : 0.18
            closeButton.animator().alphaValue = isHovered && !isRenaming ? 1 : 0
        }

        // Renombrar en la propia fila.
        if isRenaming != self.isRenaming {
            self.isRenaming = isRenaming
            renameField.isHidden = !isRenaming
            title.isHidden = isRenaming
            if isRenaming {
                renameField.stringValue = tab.displayTitle
                renameField.textColor = colors.title
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    window?.makeFirstResponder(renameField)
                    renameField.currentEditor()?.selectAll(nil)
                }
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 16
        var x = 10 + indent
        let midY = bounds.midY
        let hasSubtitle = !subtitle.isHidden
        faviconBox.frame = CGRect(x: x - 2.5, y: midY - (size + 5) / 2, width: size + 5, height: size + 5)
        favicon.frame = CGRect(x: 2.5, y: 2.5, width: size, height: size)
        let ringPath = CGPath(ellipseIn: faviconBox.bounds.insetBy(dx: 0.8, dy: 0.8), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [ringTrack, ring] {
            shape.frame = faviconBox.bounds
            shape.path = ringPath
        }
        // El progreso empieza arriba y gira en el sentido del reloj.
        ring.setAffineTransform(CGAffineTransform(translationX: faviconBox.bounds.midX, y: faviconBox.bounds.midY)
            .rotated(by: .pi / 2).scaledBy(x: 1, y: -1).translatedBy(x: -faviconBox.bounds.midX, y: -faviconBox.bounds.midY))
        CATransaction.commit()
        x += size + 8
        if !slashButton.isHidden {
            slashButton.frame = CGRect(x: x - 2, y: midY - 11, width: 12, height: 22)
            x += 10
        }
        let width = max(0, bounds.width - x - 4)
        let lineHeight: CGFloat = 17
        if hasSubtitle {
            title.frame = CGRect(x: x, y: midY - lineHeight + 1, width: width, height: lineHeight)
            subtitle.frame = CGRect(x: x, y: midY + 1, width: width, height: 15)
        } else {
            title.frame = CGRect(x: x, y: midY - lineHeight / 2, width: width, height: lineHeight)
        }
        renameField.frame = CGRect(x: x - 2, y: midY - 9, width: width, height: 18)
        closeButton.frame = CGRect(x: bounds.width - 4 - 22, y: midY - 11, width: 22, height: 22)
    }

    private func symbol(_ name: String, tint: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [tint]))
    }

    @objc private func closeTab() {
        guard let tab else { return }
        if removesPinned { coordinator?.browser.removePinned(tab) } else { coordinator?.browser.close(tab) }
    }

    @objc private func returnToPinned() {
        guard let tab else { return }
        coordinator?.browser.returnToPinnedURL(tab)
    }

    // MARK: Renombrar

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isRenaming, let tab, let browser = coordinator?.browser, browser.renamingTabID == tab.id else { return }
        browser.rename(tab, to: renameField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            coordinator?.browser.renamingTabID = nil
            return true
        }
        return false
    }
}

// MARK: - Carpeta

final class FolderCellView: NSView, NSTextFieldDelegate {
    weak var coordinator: SidebarListCoordinator?
    private(set) var folder: Folder?
    private let icon = NSImageView()
    private let name = FadingLabel()
    private let renameField = NSTextField()
    private var isRenaming = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(icon)
        name.field.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(name)
        renameField.isBordered = false
        renameField.drawsBackground = false
        renameField.focusRingType = .none
        renameField.font = .systemFont(ofSize: 13, weight: .semibold)
        renameField.delegate = self
        renameField.isHidden = true
        addSubview(renameField)
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override var isFlipped: Bool { true }

    func configure(folder: Folder, isRenaming: Bool, colors: SidebarColors) {
        self.folder = folder
        icon.image = NSImage(systemSymbolName: folder.isExpanded ? "folder" : "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular).applying(.init(paletteColors: [colors.title])))
        name.field.stringValue = folder.name
        name.field.textColor = colors.title
        if isRenaming != self.isRenaming {
            self.isRenaming = isRenaming
            renameField.isHidden = !isRenaming
            name.isHidden = isRenaming
            if isRenaming {
                renameField.stringValue = folder.name
                renameField.textColor = colors.title
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    window?.makeFirstResponder(renameField)
                    renameField.currentEditor()?.selectAll(nil)
                }
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        icon.frame = CGRect(x: 10, y: bounds.midY - 8, width: 16, height: 16)
        let x: CGFloat = 10 + 16 + 8
        name.frame = CGRect(x: x, y: bounds.midY - 8.5, width: max(0, bounds.width - x - 8), height: 17)
        renameField.frame = CGRect(x: x - 2, y: bounds.midY - 9, width: max(0, bounds.width - x - 8), height: 18)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isRenaming, let folder else { return }
        let text = renameField.stringValue.trimmingCharacters(in: .whitespaces)
        coordinator?.finishRenaming(folder, to: text.isEmpty ? folder.name : text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            coordinator?.finishRenaming(nil, to: "")
            return true
        }
        return false
    }
}

// MARK: - Separador y "Nueva pestaña"

/// Línea entre fijadas y Hoy; al pasar el ratón aparece "Limpiar" (archiva las de Hoy).
final class SeparatorCellView: NSView {
    weak var coordinator: SidebarListCoordinator?
    private let line = CALayer()
    private let cleanButton = NSButton(title: "Limpiar", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(line)
        cleanButton.isBordered = false
        cleanButton.wantsLayer = true
        cleanButton.layer?.cornerRadius = 6
        cleanButton.target = self
        cleanButton.action = #selector(clean)
        cleanButton.alphaValue = 0
        cleanButton.toolTip = "Archivar las pestañas de Hoy"
        addSubview(cleanButton)
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override var isFlipped: Bool { true }

    func configure(isHovered: Bool, hasTodayTabs: Bool, colors: SidebarColors) {
        line.backgroundColor = colors.title.withAlphaComponent(0.10).cgColor
        cleanButton.attributedTitle = NSAttributedString(string: "Limpiar", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: colors.subtitle,
        ])
        cleanButton.layer?.backgroundColor = colors.hover.cgColor
        let shows = isHovered && hasTodayTabs
        cleanButton.isEnabled = shows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = shows ? 0.08 : 0.22
            cleanButton.animator().alphaValue = shows ? 1 : 0
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttonWidth: CGFloat = cleanButton.alphaValue > 0 ? 58 : 0
        cleanButton.frame = CGRect(x: bounds.width - 8 - 58, y: bounds.midY - 9, width: 58, height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.frame = CGRect(x: 8, y: bounds.midY, width: max(0, bounds.width - 16 - (buttonWidth > 0 ? 66 : 0)), height: 1)
        CATransaction.commit()
    }

    @objc private func clean() {
        coordinator?.browser.archiveTodayTabs(keepingSelected: false)
    }
}

final class NewTabCellView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "Nueva pestaña")

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(icon)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    override var isFlipped: Bool { true }

    func configure(colors: SidebarColors) {
        icon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold).applying(.init(paletteColors: [colors.subtitle])))
        label.textColor = colors.subtitle
    }

    override func layout() {
        super.layout()
        icon.frame = CGRect(x: 10, y: bounds.midY - 8, width: 16, height: 16)
        let height = label.intrinsicContentSize.height
        label.frame = CGRect(x: 34, y: bounds.midY - height / 2, width: max(0, bounds.width - 40), height: height)
    }
}
