import SwiftUI
import AppKit

/// Una entrada de un menú nativo (AppKit).
///
/// Los menús de SwiftUI (`.contextMenu`, `Menu`) dependen del estado de la vista: si la barra
/// lateral se recalcula mientras el menú está abierto, SwiftUI puede reconstruir su dueño y el
/// menú queda "huérfano" en pantalla, sin responder (cursor de espera). Estos menús se crean en
/// el momento del clic con el estado de ese instante y los posee AppKit, como en Arc o Safari.
public enum MenuEntry {
    case item(String, isEnabled: Bool, isChecked: Bool, isDestructive: Bool, action: @MainActor () -> Void)
    case submenu(String, isEnabled: Bool, [MenuEntry])
    case separator

    public static func button(
        _ title: String,
        enabled: Bool = true,
        checked: Bool = false,
        destructive: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> MenuEntry {
        .item(title, isEnabled: enabled, isChecked: checked, isDestructive: destructive, action: action)
    }

    public static func menu(_ title: String, enabled: Bool = true, _ entries: [MenuEntry]) -> MenuEntry {
        .submenu(title, isEnabled: enabled, entries)
    }
}

public extension NSMenu {
    /// Abre un menú nativo bajo el cursor (para botones normales que muestran un menú al pulsarlos).
    static func popUpAtMouse(_ entries: [MenuEntry]) {
        build(entries).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Construye un menú de AppKit a partir de entradas.
    static func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case let .item(title, isEnabled, isChecked, isDestructive, action):
                let item = ClosureMenuItem(title: title, action: action)
                item.isEnabled = isEnabled
                item.state = isChecked ? .on : .off
                if isDestructive {
                    item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
                }
                menu.addItem(item)
            case let .submenu(title, isEnabled, children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = build(children)
                item.isEnabled = isEnabled && !children.isEmpty
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}

/// Elemento de menú que ejecuta un bloque. La acción se lanza en el siguiente ciclo, cuando el
/// menú ya se cerró (así una alerta o un editor que abra no compite con el menú).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

    @objc private func fire() {
        let handler = handler
        DispatchQueue.main.async { handler() }
    }
}

public extension View {
    /// Menú contextual nativo (clic derecho o ⌃clic). `entries` se evalúa al abrirlo.
    ///
    /// La fila solo anota dónde está; un único `ContextMenuCatcher` en la ventana atiende el clic
    /// derecho. (Antes cada fila llevaba su propia vista de AppKit: con decenas de pestañas, mover
    /// todas esas vistas en cada fotograma hacía que las animaciones de la barra fueran a saltos.)
    func nativeContextMenu(_ entries: @escaping @MainActor () -> [MenuEntry]) -> some View {
        modifier(ContextMenuRegion(entries: entries))
    }

    /// Convierte la vista en un botón que abre un menú nativo debajo de ella al hacer clic.
    func nativeMenuOnClick(_ entries: @escaping @MainActor () -> [MenuEntry]) -> some View {
        overlay(NativeMenuArea(trigger: .anyClick, entries: entries))
    }
}

private struct NativeMenuArea: NSViewRepresentable {
    enum Trigger { case contextClick, anyClick }

    let trigger: Trigger
    let entries: @MainActor () -> [MenuEntry]

    func makeNSView(context: Context) -> AreaView {
        AreaView()
    }

    func updateNSView(_ view: AreaView, context: Context) {
        view.trigger = trigger
        view.entries = entries
    }

    final class AreaView: NSView {
        var trigger: Trigger = .contextClick
        var entries: @MainActor () -> [MenuEntry] = { [] }

        /// Solo se queda con los clics que abren el menú; el resto (clic normal, hover, arrastre)
        /// pasa a la vista de SwiftUI de debajo.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, isContextClick(event) || (trigger == .anyClick && event.type == .leftMouseDown) else {
                return nil
            }
            return super.hitTest(point)
        }

        private func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }

        override func rightMouseDown(with event: NSEvent) {
            NSMenu.popUpContextMenu(.build(entries()), with: event, for: self)
        }

        override func mouseDown(with event: NSEvent) {
            if isContextClick(event) || trigger == .contextClick {
                NSMenu.popUpContextMenu(.build(entries()), with: event, for: self)
            } else {
                // Debajo del botón, alineado a su borde izquierdo (como un menú desplegable).
                let origin = NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4)
                NSMenu.build(entries()).popUp(positioning: nil, at: origin, in: self)
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - Un solo receptor de clic derecho para toda la ventana

/// Zonas con menú contextual, en coordenadas de la ventana (origen arriba a la izquierda).
@MainActor
final class ContextMenuRegistry {
    static let shared = ContextMenuRegistry()

    struct Region {
        var frame: CGRect
        var entries: @MainActor () -> [MenuEntry]
    }

    private var regions: [UUID: Region] = [:]

    func set(_ id: UUID, frame: CGRect, entries: @escaping @MainActor () -> [MenuEntry]) {
        regions[id] = Region(frame: frame, entries: entries)
    }

    func remove(_ id: UUID) {
        regions[id] = nil
    }

    /// La zona más pequeña bajo el punto (un icono de espacio antes que la barra entera).
    func region(at point: CGPoint) -> Region? {
        regions.values.filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

private struct ContextMenuRegion: ViewModifier {
    let entries: @MainActor () -> [MenuEntry]
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                ContextMenuRegistry.shared.set(id, frame: frame, entries: entries)
            }
            .onDisappear { ContextMenuRegistry.shared.remove(id) }
    }
}

/// Va una vez sobre toda la ventana: si el clic derecho cae en una zona con menú, lo abre; si no,
/// lo deja pasar (por ejemplo, al menú contextual de la página web).
public struct ContextMenuCatcher: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> CatcherView { CatcherView() }
    public func updateNSView(_ view: CatcherView, context: Context) {}

    public final class CatcherView: NSView {
        override public func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
                  region(for: event) != nil
            else { return nil }
            return super.hitTest(point)
        }

        private func region(for event: NSEvent) -> ContextMenuRegistry.Region? {
            guard let contentView = window?.contentView else { return nil }
            let local = contentView.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: local.x, y: contentView.isFlipped ? local.y : contentView.bounds.height - local.y)
            return ContextMenuRegistry.shared.region(at: point)
        }

        private func showMenu(for event: NSEvent) {
            guard let region = region(for: event) else { return }
            NSMenu.popUpContextMenu(.build(region.entries()), with: event, for: self)
        }

        override public func rightMouseDown(with event: NSEvent) { showMenu(for: event) }
        override public func mouseDown(with event: NSEvent) { showMenu(for: event) }
        override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
