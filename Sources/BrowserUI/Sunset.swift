import SwiftUI
import BrowserCore

/// Colores de la marca Sunset (los mismos del icono): del cielo índigo al horizonte dorado.
public enum Sunset {
    public static let night = SpaceColor(red: 0.07, green: 0.04, blue: 0.15)
    public static let indigo = SpaceColor(red: 0.22, green: 0.12, blue: 0.45)
    public static let rose = SpaceColor(red: 0.85, green: 0.30, blue: 0.45)
    public static let coral = SpaceColor(red: 0.98, green: 0.30, blue: 0.45)
    public static let orange = SpaceColor(red: 1.00, green: 0.50, blue: 0.25)
    public static let amber = SpaceColor(red: 1.00, green: 0.72, blue: 0.20)
    public static let gold = SpaceColor(red: 1.00, green: 0.85, blue: 0.55)
    public static let violet = SpaceColor(red: 0.55, green: 0.36, blue: 0.95)
}

/// El símbolo de Sunset: rayos de sol saliendo del horizonte. Vectorial, se dibuja a cualquier tamaño.
public struct SunsetLogo: Shape {
    /// Ancho / alto del símbolo.
    public static let aspectRatio: CGFloat = 1.98771

    /// Los rayos, en orden: el grande, el horizonte, el alto y el pequeño. `nil` dibuja todos.
    public var ray: Int?

    public init(ray: Int? = nil) {
        self.ray = ray
    }

    /// Color sólido de cada rayo (los mismos del icono).
    public static let rayColors: [Color] = [Color(Sunset.orange), Color(Sunset.amber), Color(Sunset.coral), Color(Sunset.violet)]

    public func path(in rect: CGRect) -> Path {
        // Encaja el símbolo en el rectángulo sin deformarlo, centrado.
        let width = min(rect.width, rect.height * Self.aspectRatio)
        let height = width / Self.aspectRatio
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * width, y: origin.y + y * height)
        }

        var path = Path()
        if ray == nil || ray == 0 {
            path.move(to: p(0.52392, 0.00000))
            path.addCurve(to: p(0.29882, 0.44743), control1: p(0.39957, 0.00002), control2: p(0.29882, 0.20034))
            path.addLine(to: p(0.29881, 0.95073))
            path.addLine(to: p(0.77713, 0.00000))
            path.addLine(to: p(0.52392, 0.00000))
            path.closeSubpath()
        }
        if ray == nil || ray == 1 {
            path.move(to: p(0.82097, 0.64413))
            path.addCurve(to: p(0.50262, 0.64408), control1: p(0.73304, 0.46939), control2: p(0.59052, 0.46939))
            path.addLine(to: p(0.32358, 0.99995))
            path.addLine(to: p(1.00000, 1.00000))
            path.addLine(to: p(0.82097, 0.64413))
            path.closeSubpath()
        }
        if ray == nil || ray == 2 {
            path.move(to: p(0.14002, 0.69962))
            path.addLine(to: p(0.26631, 0.95064))
            path.addLine(to: p(0.26633, 0.00229))
            path.addLine(to: p(0.14002, 0.25335))
            path.addCurve(to: p(0.14002, 0.69962), control1: p(0.07803, 0.37660), control2: p(0.07804, 0.57641))
            path.closeSubpath()
        }
        if ray == nil || ray == 3 {
            path.move(to: p(0.00000, 0.76942))
            path.addCurve(to: p(0.11442, 0.99689), control1: p(0.00000, 0.89506), control2: p(0.05124, 0.99690))
            path.addLine(to: p(0.24315, 0.99687))
            path.addLine(to: p(0.00002, 0.51359))
            path.addLine(to: p(0.00000, 0.76942))
            path.closeSubpath()
        }
        return path
    }
}
