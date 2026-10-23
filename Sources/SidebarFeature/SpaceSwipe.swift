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
            didSwitch = false
        }
        if axis == .undecided, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 0.5 {
            axis = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.3 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return event }

        // Dirección física de los dedos (positivo = hacia la derecha), con o sin scroll natural.
        distance += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if !didSwitch, abs(distance) >= Self.threshold {
            didSwitch = true
            // Dedos hacia la izquierda: el siguiente espacio entra por la derecha.
            let step = distance < 0 ? 1 : -1
            if let index = browser.spaces.firstIndex(where: { $0.id == browser.activeSpaceID }),
               browser.spaces.indices.contains(index + step) {
                withAnimation(Theme.spring) { browser.activate(browser.spaces[index + step]) }
            } else {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
        // El evento sigue su camino: si se descarta el inicio del gesto, AppKit deja de mandar el
        // resto. La lista no se mueve en horizontal (no tiene rebote lateral).
        return event
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
