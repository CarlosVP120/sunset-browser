import SwiftUI
import QuartzCore
import BrowserCore
import BrowserUI

/// Fondo de Inicio: el color del espacio con manchas de luz suaves que se mueven muy despacio
/// (como una aurora) y el grano del tema. Pensado para quedarse en pantalla sin cansar.
///
/// Las luces se animan con Core Animation: el movimiento lo hace el compositor del sistema y la
/// app no trabaja en cada fotograma (con SwiftUI costaba ~40 % de CPU en reposo).
struct HomeBackground: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            Color(theme.background.first ?? .navy)
            AuroraLayerView(colors: Self.lights(for: theme).map { Color($0) }, isDark: theme.isDark)
            if theme.grain > 0 {
                GrainOverlay(intensity: theme.grain)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: theme)
    }

    /// Tres luces derivadas de los colores del tema, un poco más vivas que el fondo.
    private static func lights(for theme: SpaceTheme) -> [SpaceColor] {
        let seeds = theme.seeds.isEmpty ? [theme.accent] : theme.seeds
        return (0..<3).map { index in
            let seed = seeds[index % seeds.count].hsb
            let hue = seed.hue + Double(index) * 0.06
            return theme.isDark
                ? SpaceColor(hue: hue, saturation: min(1, seed.saturation * 0.8 + 0.1), brightness: 0.55 + 0.1 * Double(index))
                : SpaceColor(hue: hue, saturation: seed.saturation * 0.45, brightness: 1)
        }
    }
}

/// Las luces: capas con degradado radial que recorren elipses lentas, cada una a su ritmo.
private struct AuroraLayerView: NSViewRepresentable {
    let colors: [Color]
    let isDark: Bool

    func makeNSView(context: Context) -> AuroraView {
        AuroraView()
    }

    func updateNSView(_ view: AuroraView, context: Context) {
        view.update(colors: colors.map { NSColor($0).cgColor }, opacity: isDark ? 0.55 : 0.45)
    }

    final class AuroraView: NSView {
        private var lights: [CAGradientLayer] = []
        private var lastSize: CGSize = .zero
        /// Duración de una vuelta de cada luz, en segundos (muy lento a propósito).
        private let periods: [CFTimeInterval] = [150, 110, 85]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            for _ in periods {
                let light = CAGradientLayer()
                light.type = .radial
                light.startPoint = CGPoint(x: 0.5, y: 0.5)
                light.endPoint = CGPoint(x: 1, y: 1)
                layer?.addSublayer(light)
                lights.append(light)
            }
        }

        required init?(coder: NSCoder) { fatalError("No se usa desde Interface Builder") }

        // Solo dibuja: no recibe clics.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(colors: [CGColor], opacity: CGFloat) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            for (light, color) in zip(lights, colors) {
                light.colors = [color.copy(alpha: opacity) ?? color, color.copy(alpha: 0) ?? color]
            }
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            guard bounds.size != lastSize, bounds.width > 0 else { return }
            lastSize = bounds.size
            let diameter = max(bounds.width, bounds.height) * 1.1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, light) in lights.enumerated() {
                light.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                light.position = CGPoint(x: bounds.midX, y: bounds.midY)
                // Elipse alrededor del centro; cada luz empieza en otro punto y gira a su ritmo.
                let orbit = CGRect(x: bounds.width * 0.12, y: bounds.height * 0.18,
                                   width: bounds.width * 0.76, height: bounds.height * 0.64)
                let path = CGPath(ellipseIn: orbit, transform: nil)
                let animation = CAKeyframeAnimation(keyPath: "position")
                animation.path = path
                animation.duration = periods[index]
                animation.repeatCount = .infinity
                animation.calculationMode = .paced
                animation.timeOffset = periods[index] * Double(index) / 3
                light.add(animation, forKey: "orbit")
            }
            CATransaction.commit()
        }
    }
}
