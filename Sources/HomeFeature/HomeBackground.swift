import SwiftUI
import BrowserCore
import BrowserUI

/// Fondo de Inicio: el color del espacio con manchas de luz suaves que se mueven muy despacio
/// (como una aurora) y el grano del tema. Pensado para quedarse en pantalla sin cansar.
struct HomeBackground: View {
    let theme: SpaceTheme

    var body: some View {
        let base = theme.background.first ?? .navy
        let lights = Self.lights(for: theme)

        ZStack {
            Color(base)
            // 20 fotogramas por segundo bastan para un movimiento tan lento, y gasta menos.
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    let radius = max(size.width, size.height) * 0.55
                    for (index, light) in lights.enumerated() {
                        let phase = time * (0.035 + Double(index) * 0.012) + Double(index) * 2.1
                        let center = CGPoint(
                            x: size.width * (0.5 + 0.38 * cos(phase)),
                            y: size.height * (0.5 + 0.32 * sin(phase * 1.3))
                        )
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        canvas.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [Color(light).opacity(theme.isDark ? 0.55 : 0.45), .clear]),
                                center: center, startRadius: 0, endRadius: radius
                            )
                        )
                    }
                }
            }
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
