import SwiftUI
import BrowserCore

/// Medidas, animaciones y colores neutros de la interfaz.
/// Los colores de cada espacio vienen de `SpaceTheme` (ver `\.spaceTheme`).
public enum Theme {
    public static let primaryText = Color.white.opacity(0.90)
    public static let secondaryText = Color.white.opacity(0.50)
    public static let hover = Color.white.opacity(0.07)
    public static let selected = Color.white.opacity(0.15)
    public static let tile = Color.white.opacity(0.08)
    public static let separator = Color.white.opacity(0.10)

    /// Altura de la barra superior; centra los botones de la ventana.
    public static let toolbarHeight: CGFloat = 30
    public static let rowHeight: CGFloat = 34
    public static let cornerRadius: CGFloat = 8
    /// Espacio que ocupan los botones de cerrar/minimizar/maximizar.
    public static let windowButtonsInset: CGFloat = 76

    /// Muelle corto y amortiguado: la sensación "premium" de Arc (sin rebotes exagerados).
    public static let spring = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Para pulsaciones: más rápido.
    public static let pressSpring = Animation.spring(response: 0.18, dampingFraction: 0.75)
    /// Aparición del hover: entra rápido, sale un poco más lento.
    public static let hoverIn = Animation.easeOut(duration: 0.08)
    public static let hoverOut = Animation.easeOut(duration: 0.22)
}

public extension Color {
    init(_ color: SpaceColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

public extension NSColor {
    /// El mismo color que `Color(SpaceColor)`, para vistas de AppKit.
    convenience init(_ color: SpaceColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

private struct SpaceThemeKey: EnvironmentKey {
    static let defaultValue = SpaceTheme.default
}

public extension EnvironmentValues {
    /// Tema del espacio activo: fondo, hover, selección y textos.
    var spaceTheme: SpaceTheme {
        get { self[SpaceThemeKey.self] }
        set { self[SpaceThemeKey.self] = newValue }
    }
}

/// Icono de un espacio: un SF Symbol o un emoji.
public struct SpaceIcon: View {
    let icon: String
    var filled = false

    public init(_ icon: String, filled: Bool = false) {
        self.icon = icon
        self.filled = filled
    }

    public var body: some View {
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            Image(systemName: icon).symbolVariant(filled ? .fill : .none)
        } else {
            Text(icon)
        }
    }
}
