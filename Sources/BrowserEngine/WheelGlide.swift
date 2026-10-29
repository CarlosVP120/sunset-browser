import AppKit
import WebKit

/// La vista web de cada pestaña. La rueda de un ratón con muescas no trae más que "una línea" por
/// clic, y aunque WebKit anime cada clic (`ScrollAnimatorEnabled`) el scroll va a saltitos. Aquí cada
/// clic se reparte en un deslizamiento suave, a la frecuencia de la pantalla, que WebKit recibe como
/// si fuera el trackpad: así desplaza la página en su hilo de scroll, igual en la página que en
/// cualquier panel interno, y los clics seguidos se suman en vez de empezar de cero. Mientras se
/// desliza con la rueda la página no rebota en los bordes (eso es del trackpad), como en Chromium.
final class GlidingWebView: WKWebView {
    private var glide = WheelGlide()
    private var displayLink: CADisplayLink?
    /// El último evento de la rueda: los del deslizamiento son copias suyas (ventana, posición, teclas).
    private var template: CGEvent?
    private var lastFrame: CFTimeInterval = 0

    override func scrollWheel(with event: NSEvent) {
        // Trackpad, Magic Mouse y gestos con fases: tal cual. Con ⌘/⌥/⌃ la página puede querer otra cosa.
        guard !event.hasPreciseScrollingDeltas, event.phase.isEmpty, event.momentumPhase.isEmpty,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let cgEvent = event.cgEvent?.copy() else {
            finishGlide()
            if event.hasPreciseScrollingDeltas { setRubberBanding(true) }
            return super.scrollWheel(with: event)
        }
        template = cgEvent
        setRubberBanding(false)
        glide.add(dx: event.scrollingDeltaX * WheelGlide.pixelsPerLine, dy: event.scrollingDeltaY * WheelGlide.pixelsPerLine)
        startDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { finishGlide() }
    }

    /// Rebote en los bordes (`_rubberBandingEnabled`, por bordes: 0 ninguno, 15 todos).
    private var rubberBanding = true
    private func setRubberBanding(_ enabled: Bool) {
        guard enabled != rubberBanding else { return }
        rubberBanding = enabled
        let selector = NSSelectorFromString("_setRubberBandingEnabled:")
        guard let method = class_getInstanceMethod(WKWebView.self, selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(self, selector, enabled ? 15 : 0)
    }

    private func startDisplayLink() {
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(frame(_:)))
            let fps = Float(window?.screen?.maximumFramesPerSecond ?? 120)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastFrame = 0
        }
        displayLink?.isPaused = false
    }

    @objc private func frame(_ link: CADisplayLink) {
        // El primer fotograma avanza uno entero: el clic se nota enseguida.
        let elapsed = lastFrame == 0 ? link.targetTimestamp - link.timestamp : link.targetTimestamp - lastFrame
        lastFrame = link.targetTimestamp
        guard let step = glide.step(elapsed: elapsed) else {
            link.isPaused = true
            lastFrame = 0
            return
        }
        send(step)
    }

    /// Si el deslizamiento sigue a medias (llega el trackpad o se cierra la pestaña), se cierra el gesto.
    private func finishGlide() {
        guard let step = glide.finish() else { return }
        send(step)
        displayLink?.isPaused = true
        lastFrame = 0
    }

    private func send(_ step: WheelGlide.Step) {
        guard let template, let event = template.copy() else { return }
        // La hora de ahora (en nanosegundos desde el arranque, como los eventos de macOS): con la del
        // clic, o sin hora, WebKit calcula una velocidad disparatada y lanza la página con inercia.
        event.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: step.phase.rawValue)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(step.dy))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(step.dx))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: step.dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: step.dx)
        guard let synthesized = NSEvent(cgEvent: event) else { return }
        super.scrollWheel(with: synthesized)
    }
}

/// Las cuentas del deslizamiento: cuánto queda por recorrer y cuánto toca en cada fotograma (se
/// acerca al destino cada vez más despacio, como el scroll de Chromium). Los pasos son de puntos
/// enteros, lo que el trackpad manda, guardando el resto para el siguiente.
struct WheelGlide {
    /// Lo que WebKit desplaza por cada línea de la rueda.
    static let pixelsPerLine: CGFloat = 40
    /// Cuánto tarda en recorrer ~63 % de lo que queda: un clic suelto dura unos 250 ms.
    static let timeConstant: CFTimeInterval = 0.065

    enum Phase: Int64 { case began = 1, changed = 2, ended = 4 }
    struct Step: Equatable { var dx: CGFloat; var dy: CGFloat; var phase: Phase }

    private var remainingX: CGFloat = 0
    private var remainingY: CGFloat = 0
    private var isGliding = false

    mutating func add(dx: CGFloat, dy: CGFloat) {
        // Al cambiar de sentido se olvida lo que quedaba: la página responde al momento.
        if dy * remainingY < 0 { remainingY = 0 }
        if dx * remainingX < 0 { remainingX = 0 }
        remainingX += dx
        remainingY += dy
    }

    /// El paso de este fotograma, el cierre del gesto cuando ya se llegó, o `nil` si no hay nada.
    mutating func step(elapsed: CFTimeInterval) -> Step? {
        if abs(remainingX) < 1, abs(remainingY) < 1 {
            remainingX = 0
            remainingY = 0
            return finish()
        }
        let fraction = 1 - exp(-max(elapsed, 0.001) / Self.timeConstant)
        let dx = Self.whole(remainingX, fraction)
        let dy = Self.whole(remainingY, fraction)
        remainingX -= dx
        remainingY -= dy
        defer { isGliding = true }
        return Step(dx: dx, dy: dy, phase: isGliding ? .changed : .began)
    }

    /// Termina el gesto (lo que quedaba se descarta).
    mutating func finish() -> Step? {
        remainingX = 0
        remainingY = 0
        guard isGliding else { return nil }
        isGliding = false
        return Step(dx: 0, dy: 0, phase: .ended)
    }

    /// La parte del recorrido de este fotograma, en puntos enteros (al menos uno mientras quede algo).
    private static func whole(_ remaining: CGFloat, _ fraction: CGFloat) -> CGFloat {
        guard abs(remaining) >= 1 else { return 0 }
        let step = (remaining * fraction).rounded()
        return step == 0 ? (remaining > 0 ? 1 : -1) : step
    }
}
