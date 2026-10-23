import SwiftUI
import BrowserCore

/// Colores y medidas de la interfaz, sobre el vidrio oscuro tintado del espacio.
public enum Theme {
    public static let primaryText = Color.white.opacity(0.90)
    public static let secondaryText = Color.white.opacity(0.50)
    public static let hover = Color.white.opacity(0.07)
    public static let selected = Color.white.opacity(0.15)
    public static let tile = Color.white.opacity(0.08)
    public static let separator = Color.white.opacity(0.10)

    /// Altura de la barra superior; centra los botones de la ventana.
    public static let toolbarHeight: CGFloat = 30
    public static let sidebarWidth: CGFloat = 240
    public static let rowHeight: CGFloat = 32
    public static let cornerRadius: CGFloat = 8
    /// Espacio que ocupan los botones de cerrar/minimizar/maximizar.
    public static let windowButtonsInset: CGFloat = 76
}

public extension Color {
    init(_ color: SpaceColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
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
