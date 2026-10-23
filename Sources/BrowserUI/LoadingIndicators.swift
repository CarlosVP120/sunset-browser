import SwiftUI
import BrowserCore

/// Haz de luz ("tracing beam") que recorre el borde de la página mientras carga: una línea fina
/// de un solo color, en dos tonos (núcleo blanco y contorno oscuro) para verse en cualquier
/// página, con estela. Al terminar, el borde entero destella y se apaga.
///
/// Se anima con Core Animation: el movimiento lo hace el compositor del sistema, sin recalcular
/// la ventana en cada fotograma (con SwiftUI, cada fotograma recalculaba toda la ventana).
public struct PageEdgeGlow: View {
    let tab: BrowserTab?
    var cornerRadius: CGFloat

    public init(tab: BrowserTab?, cornerRadius: CGFloat = Theme.cornerRadius) {
        self.tab = tab
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        BeamLayerView(isLoading: tab?.isLoading == true, tabID: tab?.id, cornerRadius: cornerRadius)
            .allowsHitTesting(false)
    }
}

private struct BeamLayerView: NSViewRepresentable {
    let isLoading: Bool
    let tabID: UUID?
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> BeamView {
        BeamView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ view: BeamView, context: Context) {
        view.update(isLoading: isLoading, tabID: tabID)
    }

    final class BeamView: NSView {
        private let cornerRadius: CGFloat
        private let container = CALayer()
        private let track = CAShapeLayer()
        private let flash = CAShapeLayer()
        /// Cada tramo de la estela: contorno oscuro + núcleo blanco.
        private var slices: [(outline: CAShapeLayer, core: CAShapeLayer)] = []
        private var isLoading = false
        private var tabID: UUID?
        private var lastSize: CGSize = .zero

        /// Segundos por vuelta, largo del haz (fracción del borde) y número de tramos de la estela.
        private let period: CFTimeInterval = 1.8
        private let beamLength = 0.2
        private let sliceCount = 12

        init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(container)
            container.opacity = 0

            track.fillColor = nil
            track.strokeColor = NSColor.white.withAlphaComponent(0.3).cgColor
            track.lineWidth = 1
            track.shadowColor = NSColor.black.cgColor
            track.shadowOpacity = 0.5
            track.shadowRadius = 1
            track.shadowOffset = .zero
            container.addSublayer(track)

            for index in 0..<sliceCount {
                let strength = Float(pow(Double(index + 1) / Double(sliceCount), 1.8))
                let outline = CAShapeLayer()
                outline.fillColor = nil
                outline.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor
                outline.lineWidth = index == sliceCount - 1 ? 6.5 : 4.5
                outline.lineCap = .round
                outline.opacity = strength
                let core = CAShapeLayer()
                core.fillColor = nil
                core.strokeColor = NSColor.white.cgColor
                core.lineWidth = index == sliceCount - 1 ? 3.5 : 2
                core.lineCap = .round
                core.opacity = strength
                container.addSublayer(outline)
                container.addSublayer(core)
                slices.append((outline, core))
            }

            flash.fillColor = nil
            flash.strokeColor = NSColor.white.cgColor
            flash.lineWidth = 2
            flash.opacity = 0
            container.addSublayer(flash)
        }

        required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

        // Solo dibuja: los clics y el scroll pasan a la página de debajo.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard bounds.size != lastSize, bounds.width > 0 else { return }
            lastSize = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.frame = bounds
            let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
            let radius = max(0, cornerRadius - 1.5)
            let lap = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            // El borde dos veces seguidas: así el haz puede "dar la vuelta" sin saltos.
            let twoLaps = CGMutablePath()
            twoLaps.addPath(lap)
            twoLaps.addPath(lap)
            track.path = lap
            flash.path = lap
            for slice in slices {
                slice.outline.path = twoLaps
                slice.core.path = twoLaps
            }
            CATransaction.commit()
            if isLoading { startOrbit() }
        }

        func update(isLoading: Bool, tabID: UUID?) {
            // Al cambiar de pestaña no se anima: se muestra su estado tal cual.
            if tabID != self.tabID {
                self.tabID = tabID
                self.isLoading = isLoading
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                container.removeAllAnimations()
                container.opacity = isLoading ? 1 : 0
                CATransaction.commit()
                if isLoading { startOrbit() } else { stopOrbit() }
                return
            }
            guard isLoading != self.isLoading else { return }
            self.isLoading = isLoading
            if isLoading { begin() } else { finish() }
        }

        private func begin() {
            container.removeAllAnimations()
            startOrbit()
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = container.presentation()?.opacity ?? 0
            fadeIn.toValue = 1
            fadeIn.duration = 0.25
            container.opacity = 1
            container.add(fadeIn, forKey: "fade")
        }

        /// Destello de todo el borde y desvanecido.
        private func finish() {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0, 0.9, 0]
            pulse.keyTimes = [0, 0.25, 1]
            pulse.duration = 0.7
            flash.add(pulse, forKey: "pulse")

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.beginTime = CACurrentMediaTime() + 0.15
            fadeOut.duration = 0.6
            fadeOut.fillMode = .backwards
            container.opacity = 0
            container.add(fadeOut, forKey: "fade")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.isLoading else { return }
                self.stopOrbit()
            }
        }

        private func startOrbit() {
            let now = CACurrentMediaTime()
            let sliceLength = beamLength / Double(sliceCount)
            for (index, slice) in slices.enumerated() {
                // Posiciones en el camino de dos vueltas (0…1 = dos vueltas): avanza media unidad por vuelta.
                let end = (1 - beamLength + sliceLength * Double(index + 1)) / 2
                let start = end - sliceLength / 2
                for layer in [slice.outline, slice.core] {
                    for (key, from) in [("strokeStart", start), ("strokeEnd", end)] {
                        let animation = CABasicAnimation(keyPath: key)
                        animation.fromValue = from
                        animation.toValue = from + 0.5
                        animation.duration = period
                        animation.repeatCount = .infinity
                        animation.beginTime = now
                        layer.add(animation, forKey: key)
                    }
                }
            }
        }

        private func stopOrbit() {
            for slice in slices {
                slice.outline.removeAllAnimations()
                slice.core.removeAllAnimations()
            }
        }
    }
}

/// Icono de pestaña con un anillo de progreso alrededor mientras carga.
public struct LoadingFavicon: View {
    let tab: BrowserTab
    var size: CGFloat
    @Environment(\.spaceTheme) private var theme

    public init(tab: BrowserTab, size: CGFloat = 16) {
        self.tab = tab
        self.size = size
    }

    public var body: some View {
        FaviconView(tab: tab, size: size)
            .scaleEffect(tab.isLoading ? 0.78 : 1)
            .overlay {
                if tab.isLoading {
                    ZStack {
                        Circle().stroke(Color(theme.title).opacity(0.15), lineWidth: 1.6)
                        Circle()
                            .trim(from: 0, to: max(0.08, tab.progress))
                            .stroke(Color(theme.accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Color(theme.accent).opacity(0.6), radius: 2)
                    }
                    .frame(width: size + 5, height: size + 5)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: tab.isLoading)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: tab.progress)
    }
}
