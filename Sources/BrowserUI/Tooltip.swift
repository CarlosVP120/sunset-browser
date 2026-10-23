import SwiftUI

public extension View {
    /// Tooltip al estilo Arc: cápsula oscura con el texto y, si lo hay, el atajo en teclas.
    /// - Parameter shortcut: las teclas tal cual se ven, p. ej. "⌘S" o "⇧⌘T".
    func tooltip(_ text: String, shortcut: String? = nil) -> some View {
        modifier(TooltipModifier(text: text, shortcut: shortcut))
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    let shortcut: String?
    /// La posición se guarda en una caja (no en @State): cambia en cada fotograma mientras la barra
    /// lateral se anima, y como @State obligaba a redibujar cada fila en cada fotograma.
    @State private var box = FrameBox()
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.frame = $0 }
            .onHover { hovering in
                if hovering {
                    TooltipController.shared.show(text: text, shortcut: shortcut, below: box.frame, owner: id)
                } else {
                    TooltipController.shared.hide(owner: id)
                }
            }
            // Al hacer clic, el tooltip se aparta (como en macOS).
            .simultaneousGesture(TapGesture().onEnded { TooltipController.shared.hide(owner: id) })
            .onDisappear { TooltipController.shared.hide(owner: id) }
            .accessibilityHint(shortcut.map { "\(text) (\($0))" } ?? text)
    }
}

/// Una posición que no redibuja la vista al cambiar.
final class FrameBox {
    var frame: CGRect = .zero
}

/// Muestra un único tooltip flotante en una ventana propia, para que nunca quede recortado
/// por la barra lateral, una lista con scroll o el borde de la ventana.
@MainActor
final class TooltipController {
    static let shared = TooltipController()

    private let panel: NSPanel
    private let hostingView: NSHostingView<TooltipBubble>
    private var pending: Task<Void, Never>?
    /// De quién es el tooltip actual. Al pasar de un botón a otro, macOS puede avisar de la entrada
    /// en el nuevo antes que de la salida del anterior: esa salida no debe borrar el tooltip nuevo.
    private var owner: UUID?
    private var hiddenAt = Date.distantPast
    private var isShowing = false

    /// Espera antes del primer tooltip; si ya había uno visible hace poco, el siguiente sale al instante.
    private static let delay: Duration = .milliseconds(600)
    private static let warmWindow: TimeInterval = 0.8

    private init() {
        hostingView = NSHostingView(rootView: TooltipBubble(text: "", shortcut: nil))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = hostingView
    }

    func show(text: String, shortcut: String?, below frame: CGRect, owner: UUID? = nil) {
        pending?.cancel()
        self.owner = owner
        let isWarm = isShowing || Date().timeIntervalSince(hiddenAt) < Self.warmWindow
        pending = Task { [weak self] in
            if !isWarm { try? await Task.sleep(for: Self.delay) }
            guard !Task.isCancelled else { return }
            self?.present(text: text, shortcut: shortcut, below: frame, animated: !isWarm)
        }
    }

    /// Oculta el tooltip; con `owner`, solo si es suyo (sin él, cualquiera: p. ej. al abrir un menú).
    func hide(owner: UUID? = nil) {
        if let owner, owner != self.owner { return }
        self.owner = nil
        pending?.cancel()
        guard isShowing else { return }
        isShowing = false
        hiddenAt = Date()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // Si mientras tanto se mostró otro tooltip (pasar de un botón al de al lado), la ventana
            // es suya: no se quita. Antes se miraba la transparencia, y el tooltip nuevo empieza
            // transparente para aparecer con un fundido: se borraba justo al nacer.
            Task { @MainActor in
                guard let self, !self.isShowing else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func present(text: String, shortcut: String?, below frame: CGRect, animated: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let contentView = window.contentView,
              window.isVisible, frame != .zero else { return }

        hostingView.rootView = TooltipBubble(text: text, shortcut: shortcut)
        let size = hostingView.fittingSize

        // El marco llega en coordenadas de SwiftUI (origen arriba a la izquierda de la ventana).
        func screenPoint(x: CGFloat, y: CGFloat) -> NSPoint {
            let viewPoint = NSPoint(x: x, y: contentView.isFlipped ? y : contentView.bounds.height - y)
            return window.convertPoint(toScreen: contentView.convert(viewPoint, to: nil))
        }
        let below = screenPoint(x: frame.midX, y: frame.maxY)
        let above = screenPoint(x: frame.midX, y: frame.minY)
        let gap: CGFloat = 6
        var origin = NSPoint(x: below.x - size.width / 2, y: below.y - gap - size.height)

        // Que no se salga de la pantalla: si no cabe debajo, va encima.
        if let screen = window.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = above.y + gap }
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        }

        let finalFrame = NSRect(origin: origin, size: size)
        if animated || !isShowing {
            // Entra con un fundido y un pequeño desplazamiento hacia su sitio.
            panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 4), display: false)
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(finalFrame, display: true)
            }
        } else {
            // Pasando de un botón a otro: el tooltip se desliza al nuevo sitio.
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(finalFrame, display: true)
            }
        }
        isShowing = true
    }
}

/// La cápsula del tooltip.
struct TooltipBubble: View {
    let text: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            if let shortcut {
                ShortcutKeys(shortcut)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, shortcut == nil ? 11 : 5)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.10).opacity(0.96))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}

/// Un atajo dibujado como teclas ("⇧⌘R" → ⇧ ⌘ R).
public struct ShortcutKeys: View {
    let shortcut: String
    var isOnLightBackground: Bool

    public init(_ shortcut: String, onLightBackground: Bool = false) {
        self.shortcut = shortcut
        self.isOnLightBackground = onLightBackground
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                Text(String(key))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOnLightBackground ? Color.white.opacity(0.9) : Color(white: 0.16))
                    .frame(minWidth: 19, minHeight: 19)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isOnLightBackground ? Color(white: 0.35) : Color(white: 0.88))
                            .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                    )
            }
        }
    }
}
