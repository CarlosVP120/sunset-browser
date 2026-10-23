import SwiftUI
import BrowserCore
import BrowserUI

/// Borde derecho de la barra lateral, como en Arc:
/// - arrastrar cambia el ancho;
/// - por debajo del mínimo hay una resistencia elástica y, si sigues, la barra se colapsa
///   en ese momento (sin soltar); al volver hacia la derecha, reaparece;
/// - vibración en el trackpad al colapsar o reabrir; doble clic vuelve al ancho por defecto.
struct SidebarResizeHandle: NSViewRepresentable {
    let browser: Browser
    @Binding var isResizing: Bool

    static let defaultWidth: Double = 240
    /// Cuánto hay que pasar del mínimo para que se colapse.
    private static let collapseDistance: Double = 70

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        let resizer = context.coordinator
        view.onBegin = { resizer.begin() }
        view.onDrag = { resizer.drag(by: $0) }
        view.onEnd = { resizer.end() }
        view.onDoubleClick = {
            withAnimation(Theme.spring) {
                browser.sidebarWidth = Self.defaultWidth
                browser.showsSidebar = true
            }
        }
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        context.coordinator.browser = browser
        context.coordinator.isResizing = $isResizing
    }

    func makeCoordinator() -> Resizer {
        Resizer(browser: browser, isResizing: $isResizing)
    }

    @MainActor
    final class Resizer {
        var browser: Browser
        var isResizing: Binding<Bool>
        private var startWidth: Double = 0
        private var startedCollapsed = false

        init(browser: Browser, isResizing: Binding<Bool>) {
            self.browser = browser
            self.isResizing = isResizing
        }

        private var range: ClosedRange<Double> { Browser.sidebarWidthRange }

        func begin() {
            startedCollapsed = !browser.showsSidebar
            startWidth = startedCollapsed ? 0 : browser.sidebarWidth
            isResizing.wrappedValue = true
        }

        func drag(by delta: Double) {
            let proposed = startWidth + delta
            let collapseAt = range.lowerBound - collapseDistance

            if proposed < collapseAt {
                if browser.showsSidebar {
                    withAnimation(Theme.spring) { browser.showsSidebar = false }
                    haptic()
                }
                return
            }

            if !browser.showsSidebar {
                browser.sidebarWidth = range.lowerBound
                withAnimation(Theme.spring) { browser.showsSidebar = true }
                haptic()
            }

            // Fuera del rango, la barra se resiste: se mueve cada vez menos.
            let width: Double
            if proposed < range.lowerBound {
                width = range.lowerBound - rubberBand(range.lowerBound - proposed, limit: 18)
            } else if proposed > range.upperBound {
                width = range.upperBound + rubberBand(proposed - range.upperBound, limit: 30)
            } else {
                width = proposed
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { browser.sidebarWidth = width }
        }

        func end() {
            isResizing.wrappedValue = false
            guard browser.showsSidebar else {
                // Se reabrirá con el ancho que tenía.
                browser.sidebarWidth = max(startWidth, range.lowerBound)
                return
            }
            withAnimation(Theme.spring) {
                browser.sidebarWidth = min(max(browser.sidebarWidth, range.lowerBound), range.upperBound)
            }
        }

        private func rubberBand(_ distance: Double, limit: Double) -> Double {
            limit * (1 - exp(-distance / (limit * 2.5)))
        }

        private func haptic() {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    final class HandleView: NSView {
        var onBegin: (() -> Void)?
        var onDrag: ((Double) -> Void)?
        var onEnd: (() -> Void)?
        var onDoubleClick: (() -> Void)?
        private var startX: CGFloat = 0

        // Que arrastrar aquí no mueva la ventana.
        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            startX = event.locationInWindow.x
            onBegin?()
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(event.locationInWindow.x - startX)
        }

        override func mouseUp(with event: NSEvent) {
            guard event.clickCount < 2 else { return }
            onEnd?()
        }
    }
}
