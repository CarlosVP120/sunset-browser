import Foundation

/// Color RGBA (0–1), guardable en disco.
public struct SpaceColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        red = try container.decode(Double.self, forKey: .red)
        green = try container.decode(Double.self, forKey: .green)
        blue = try container.decode(Double.self, forKey: .blue)
        alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
    }

    public func mixed(with other: SpaceColor, by amount: Double, alpha: Double? = nil) -> SpaceColor {
        SpaceColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount,
            alpha: alpha ?? self.alpha
        )
    }

    public static let navy = SpaceColor(red: 0.098, green: 0.180, blue: 0.314)
    public static let plum = SpaceColor(red: 0.243, green: 0.129, blue: 0.290)
    public static let forest = SpaceColor(red: 0.090, green: 0.235, blue: 0.188)
    public static let ember = SpaceColor(red: 0.322, green: 0.141, blue: 0.098)
    public static let palette: [SpaceColor] = [.navy, .plum, .forest, .ember]
}

/// Tema de un espacio, con la misma estructura que usa Arc (`windowTheme`).
public struct SpaceTheme: Codable, Equatable, Sendable {
    /// Uno o varios colores de fondo (varios = degradado).
    public var background: [SpaceColor]
    /// Intensidad del grano, de 0 a 1.
    public var grain: Double
    /// Si el contenido sobre el fondo es claro (fondo oscuro).
    public var isDark: Bool
    /// Fondo de una fila al pasar el ratón.
    public var hover: SpaceColor
    /// Fondo de la pestaña seleccionada.
    public var focus: SpaceColor
    public var title: SpaceColor
    public var subtitle: SpaceColor
    public var accent: SpaceColor

    public init(
        background: [SpaceColor],
        grain: Double,
        isDark: Bool,
        hover: SpaceColor,
        focus: SpaceColor,
        title: SpaceColor,
        subtitle: SpaceColor,
        accent: SpaceColor
    ) {
        self.background = background
        self.grain = grain
        self.isDark = isDark
        self.hover = hover
        self.focus = focus
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
    }

    /// Tema oscuro derivado de un color, con las mismas proporciones que los temas de Arc.
    public static func dark(from base: SpaceColor, grain: Double = 0.35) -> SpaceTheme {
        let gray = SpaceColor(red: 0.6, green: 0.6, blue: 0.6)
        let white = SpaceColor(red: 1, green: 1, blue: 1)
        return SpaceTheme(
            background: [base],
            grain: grain,
            isDark: true,
            hover: base.mixed(with: gray, by: 0.5, alpha: 0.48),
            focus: base.mixed(with: gray, by: 0.4, alpha: 0.80),
            title: SpaceColor(red: 0.867, green: 0.878, blue: 0.898),
            subtitle: SpaceColor(red: 0.459, green: 0.471, blue: 0.482),
            accent: base.mixed(with: white, by: 0.45)
        )
    }

    public static let `default` = dark(from: .navy)
}
