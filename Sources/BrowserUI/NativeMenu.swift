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
    func nativeContextMenu(_ entries: @escaping @MainActor () -> [MenuEntry]) -> some View {
        overlay(NativeMenuArea(trigger: .contextClick, entries: entries))
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
