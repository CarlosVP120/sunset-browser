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

extension SpaceColor {
    /// Color a partir de tono, saturación y brillo (0–1).
    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    /// Tono, saturación y brillo (0–1).
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxValue == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }
}

/// Tema de un espacio, con la misma estructura que usa Arc (`windowTheme`).
public struct SpaceTheme: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable, CaseIterable {
        /// Sigue el modo claro/oscuro del sistema.
        case auto, light, dark
    }

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

    /// Lo que se elige en el editor: colores puros, apariencia e intensidad.
    /// El resto del tema se genera a partir de esto.
    public var seeds: [SpaceColor]
    public var appearance: Appearance
    /// Cuánto color tiene el fondo, de 0 (casi neutro) a 1 (muy intenso).
    public var intensity: Double

    public init(
        background: [SpaceColor],
        grain: Double,
        isDark: Bool,
        hover: SpaceColor,
        focus: SpaceColor,
        title: SpaceColor,
        subtitle: SpaceColor,
        accent: SpaceColor,
        seeds: [SpaceColor]? = nil,
        appearance: Appearance? = nil,
        intensity: Double = 0.5
    ) {
        self.background = background
        self.grain = grain
        self.isDark = isDark
        self.hover = hover
        self.focus = focus
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.seeds = seeds ?? background.map(Self.seed(fromBackground:))
        self.appearance = appearance ?? (isDark ? .dark : .light)
        self.intensity = intensity
    }

    private enum CodingKeys: String, CodingKey {
        case background, grain, isDark, hover, focus, title, subtitle, accent, seeds, appearance, intensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            background: try c.decode([SpaceColor].self, forKey: .background),
            grain: try c.decode(Double.self, forKey: .grain),
            isDark: try c.decode(Bool.self, forKey: .isDark),
            hover: try c.decode(SpaceColor.self, forKey: .hover),
            focus: try c.decode(SpaceColor.self, forKey: .focus),
            title: try c.decode(SpaceColor.self, forKey: .title),
            subtitle: try c.decode(SpaceColor.self, forKey: .subtitle),
            accent: try c.decode(SpaceColor.self, forKey: .accent),
            seeds: try c.decodeIfPresent([SpaceColor].self, forKey: .seeds),
            appearance: try c.decodeIfPresent(Appearance.self, forKey: .appearance),
            intensity: try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.5
        )
    }

    /// El color puro que corresponde a un fondo ya oscurecido (para temas importados).
    static func seed(fromBackground color: SpaceColor) -> SpaceColor {
        let hsb = color.hsb
        return SpaceColor(hue: hsb.hue, saturation: min(1, hsb.saturation * 1.1), brightness: 1)
    }

    /// Genera el tema completo a partir de lo elegido en el editor.
    public static func make(
        seeds: [SpaceColor],
        appearance: Appearance,
        intensity: Double,
        grain: Double,
        systemIsDark: Bool = true
    ) -> SpaceTheme {
        let seeds = seeds.isEmpty ? [SpaceTheme.seed(fromBackground: .navy)] : seeds
        let isDark = appearance == .dark || (appearance == .auto && systemIsDark)
        let white = SpaceColor(red: 1, green: 1, blue: 1)
        let black = SpaceColor(red: 0, green: 0, blue: 0)

        let background = seeds.map { seed -> SpaceColor in
            let hsb = seed.hsb
            if isDark {
                // Oscuro: el color se apaga; con más intensidad, más saturado y luminoso.
                return SpaceColor(hue: hsb.hue,
                                  saturation: hsb.saturation * (0.45 + intensity * 0.45),
                                  brightness: 0.16 + intensity * 0.30)
            } else {
                // Claro: un pastel; con más intensidad, más color.
                return SpaceColor(hue: hsb.hue,
                                  saturation: hsb.saturation * (0.08 + intensity * 0.38),
                                  brightness: 0.97 - intensity * 0.07)
            }
        }
        let base = background[0]
        let gray = SpaceColor(red: 0.6, green: 0.6, blue: 0.6)

        if isDark {
            return SpaceTheme(
                background: background, grain: grain, isDark: true,
                hover: base.mixed(with: gray, by: 0.5, alpha: 0.48),
                focus: base.mixed(with: gray, by: 0.4, alpha: 0.80),
                title: SpaceColor(red: 0.867, green: 0.878, blue: 0.898),
                subtitle: SpaceColor(red: 0.459, green: 0.471, blue: 0.482),
                accent: seeds[0].mixed(with: white, by: 0.25),
                seeds: seeds, appearance: appearance, intensity: intensity
            )
        }
        return SpaceTheme(
            background: background, grain: grain, isDark: false,
            hover: base.mixed(with: black, by: 0.5, alpha: 0.08),
            focus: SpaceColor(red: 1, green: 1, blue: 1, alpha: 0.82),
            title: SpaceColor(red: 0.12, green: 0.13, blue: 0.15),
            subtitle: SpaceColor(red: 0.45, green: 0.47, blue: 0.5),
            accent: seeds[0].mixed(with: black, by: 0.2),
            seeds: seeds, appearance: appearance, intensity: intensity
        )
    }

    /// El tema tal como se dibuja: si sigue al sistema y el modo no coincide, se regenera.
    public func resolved(systemIsDark: Bool) -> SpaceTheme {
        guard appearance == .auto, isDark != systemIsDark else { return self }
        return .make(seeds: seeds, appearance: .auto, intensity: intensity, grain: grain, systemIsDark: systemIsDark)
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

    /// Colores sugeridos en el editor (como la fila de muestras de Arc).
    public static let presetSeeds: [[SpaceColor]] = [
        [SpaceColor(hue: 0.08, saturation: 0.06, brightness: 1)],
        [SpaceColor(hue: 0.94, saturation: 0.45, brightness: 1)],
        [SpaceColor(hue: 0.83, saturation: 0.45, brightness: 0.85)],
        [SpaceColor(hue: 0.99, saturation: 0.68, brightness: 1)],
        [SpaceColor(hue: 0.06, saturation: 0.72, brightness: 1)],
        [SpaceColor(hue: 0.14, saturation: 0.7, brightness: 1)],
        [SpaceColor(hue: 0.41, saturation: 0.72, brightness: 0.95)],
        [SpaceColor(hue: 0.55, saturation: 0.55, brightness: 0.95)],
        [SpaceColor(hue: 0.66, saturation: 0.4, brightness: 0.85)],
        [SpaceColor(hue: 0.62, saturation: 0.75, brightness: 1), SpaceColor(hue: 0.8, saturation: 0.6, brightness: 1)],
        [SpaceColor(hue: 0.97, saturation: 0.6, brightness: 1), SpaceColor(hue: 0.08, saturation: 0.7, brightness: 1)],
        [SpaceColor(hue: 0.45, saturation: 0.6, brightness: 1), SpaceColor(hue: 0.58, saturation: 0.7, brightness: 1)],
        [SpaceColor(hue: 0.75, saturation: 0.5, brightness: 1), SpaceColor(hue: 0.92, saturation: 0.5, brightness: 1),
         SpaceColor(hue: 0.08, saturation: 0.5, brightness: 1)],
        [SpaceColor(hue: 0.55, saturation: 0.8, brightness: 1), SpaceColor(hue: 0.33, saturation: 0.6, brightness: 1)],
        [SpaceColor(hue: 0, saturation: 0, brightness: 0.6)],
        [SpaceColor(hue: 0.1, saturation: 0.35, brightness: 0.9)],
        [SpaceColor(hue: 0.5, saturation: 0.35, brightness: 0.9)],
        [SpaceColor(hue: 0.7, saturation: 0.8, brightness: 1), SpaceColor(hue: 0.55, saturation: 0.9, brightness: 1)],
    ]
}
