import AppKit
import Observation

/// Sabe si hay un menú abierto (contextual o de la barra de menús).
///
/// Mientras un menú está abierto, cada fotograma de una animación de SwiftUI obliga a recalcular
/// la ventana entera, y el menú se queda sin tiempo para responder (se congela). Las animaciones
/// continuas (fondo de Inicio, reloj, haz de carga) se pausan mientras esto sea `true`.
@MainActor
@Observable
public final class MenuTracking {
    public static let shared = MenuTracking()

    public private(set) var isTracking = false
    /// Los submenús abren y cierran su propio seguimiento: se cuentan para no despausar antes de tiempo.
    @ObservationIgnored private var depth = 0

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuTracking.shared.changeDepth(by: 1) }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuTracking.shared.changeDepth(by: -1) }
        }
    }

    /// Hay que llamarlo una vez al arrancar para empezar a escuchar.
    public static func start() {
        _ = shared
    }

    private func changeDepth(by delta: Int) {
        depth = max(0, depth + delta)
        let tracking = depth > 0
        if tracking != isTracking { isTracking = tracking }
        // Un tooltip no debe quedarse flotando encima de un menú.
        if tracking { TooltipController.shared.hide() }
    }
}
