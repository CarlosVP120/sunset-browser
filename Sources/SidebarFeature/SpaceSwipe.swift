import AppKit
import SwiftUI
import BrowserCore
import BrowserUI

/// Deslizar dos dedos en horizontal sobre la barra lateral cambia de espacio (como en Arc).
/// Solo el trackpad (los gestos con fase); el scroll vertical y el ratón siguen igual.
struct SpaceSwipeCatcher: NSViewRepresentable {
    let browser: Browser

    func makeNSView(context: Context) -> SpaceSwipeView {
        let view = SpaceSwipeView()
        view.browser = browser
        return view
    }

    func updateNSView(_ view: SpaceSwipeView, context: Context) {
        view.browser = browser
    }
}

final class SpaceSwipeView: NSView {
    weak var browser: Browser?
    private var monitor: Any?
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var distance: CGFloat = 0
    /// Recorrido mientras aún no se sabe si el gesto es horizontal o vertical.
    private var pending = CGSize.zero
    private var didSwitch = false
    /// Recorrido de los dedos (en puntos) para pasar al siguiente espacio.
    private static let threshold: CGFloat = 40

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        // Los monitores locales se llaman en el hilo principal.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let event = event
            nonisolated(unsafe) var result: NSEvent? = event
            MainActor.assumeIsolated { result = self?.handle(event) ?? event }
            return result
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window == nil || event.window === window, let browser else { return event }
        guard !event.phase.isEmpty else { return event }

        if event.phase == .began || event.phase == .mayBegin {
            // Sin ventana (eventos enviados al proceso) la posición viene en coordenadas de pantalla.
            let location = event.window == nil ? window.convertPoint(fromScreen: event.locationInWindow) : event.locationInWindow
            guard bounds.contains(convert(location, from: nil)) else {
                axis = .vertical
                return event
            }
            axis = .undecided
            distance = 0
            pending = .zero
            didSwitch = false
            // Con «Deslizar entre páginas» activado (lo normal), AppKit reserva el resto de un
            // gesto horizontal para el seguimiento de deslizamiento: hay que pedirlo aquí, con el
            // evento de inicio, como hace Safari para atrás/adelante.
            if event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
               abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                trackSwipe(event, browser: browser)
                return nil
            }
        }
        // Dirección física de los dedos (positivo = hacia la derecha), con o sin scroll natural.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if axis == .undecided {
            // Se decide tras unos puntos de recorrido: el primer evento del trackpad suele traer
            // un poco de movimiento vertical aunque el gesto sea horizontal.
            pending.width += abs(event.scrollingDeltaX)
            pending.height += abs(event.scrollingDeltaY)
            distance += dx
            guard pending.width + pending.height >= 6 else { return event }
            axis = pending.width > pending.height * 1.2 ? .horizontal : .vertical
        } else {
            distance += dx
        }
        guard axis == .horizontal else { return event }

        if !didSwitch, abs(distance) >= Self.threshold {
            didSwitch = true
            // Dedos hacia la izquierda: el siguiente espacio entra por la derecha.
            switchSpace(by: distance < 0 ? 1 : -1, browser: browser)
        }
        // El evento sigue su camino: si se descarta el inicio del gesto, AppKit deja de mandar el
        // resto. La lista no se mueve en horizontal (no tiene rebote lateral).
        return event
    }

    private func switchSpace(by step: Int, browser: Browser) {
        if let index = browser.spaces.firstIndex(where: { $0.id == browser.activeSpaceID }),
           browser.spaces.indices.contains(index + step) {
            withAnimation(Theme.spring) { browser.activate(browser.spaces[index + step]) }
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Seguimiento del sistema: `gestureAmount` positivo es dedos a la derecha (espacio anterior).
    private func trackSwipe(_ event: NSEvent, browser: Browser) {
        let index = browser.spaces.firstIndex { $0.id == browser.activeSpaceID } ?? 0
        let hasPrevious = index > 0, hasNext = index < browser.spaces.count - 1
        var switched = false
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: hasNext ? -1 : 0,
                              max: hasPrevious ? 1 : 0) { [weak self] amount, phase, _, _ in
            // Al soltar con recorrido suficiente el sistema manda `.ended` (si no, `.cancelled`).
            guard phase == .ended, !switched, amount != 0, let self else { return }
            switched = true
            MainActor.assumeIsolated { self.switchSpace(by: amount > 0 ? -1 : 1, browser: browser) }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

