import SwiftUI
import BrowserCore

/// Desenfoque nativo de macOS que deja ver lo que hay detrás de la ventana.
public struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var isDark: Bool

    public init(material: NSVisualEffectView.Material = .hudWindow, isDark: Bool = true) {
        self.material = material
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

/// Fondo de la ventana como en Arc: vidrio translúcido, color (o degradado) del espacio y grano.
public struct SpaceBackground: View {
    let theme: SpaceTheme

    public init(theme: SpaceTheme) {
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            VisualEffectBlur(isDark: theme.isDark)

            // "translucencyStyle: light" de Arc: el color cubre casi todo, pero se intuye el escritorio.
            if theme.background.count > 1 {
                LinearGradient(colors: theme.background.map { Color($0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.86)
            } else {
                Color(theme.background.first ?? .navy).opacity(0.84)
            }

            // Luz suave arriba a la izquierda, como un reflejo en el vidrio.
            RadialGradient(colors: [.white.opacity(0.08), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)

            if theme.grain > 0 {
                GrainOverlay(intensity: theme.grain)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: theme)
    }
}

/// Textura de grano (el "noise" de los temas de Arc). Se genera una sola vez y se repite.
public struct GrainOverlay: View {
    let intensity: Double

    public init(intensity: Double) {
        self.intensity = intensity
    }

    public var body: some View {
        // Fusión normal (no "overlay"): así el grano no obliga a recomponer la ventana en cada
        // fotograma mientras se hace scroll en la página.
        Image(nsImage: Self.texture)
            .resizable(resizingMode: .tile)
            .opacity(min(intensity, 1))
            .allowsHitTesting(false)
    }

    /// Puntos claros y oscuros semitransparentes: aclaran y oscurecen, como el "overlay", sin serlo.
    private static let texture: NSImage = {
        let size = 160
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var generator = SystemRandomNumberGenerator()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = Int.random(in: 0...255, using: &generator)
            let light = value > 127
            // Alfa premultiplicado: el color no puede superar al alfa.
            let alpha = UInt8(Double(abs(value - 127)) / 127 * 46)
            let color: UInt8 = light ? alpha : 0
            pixels[index] = color
            pixels[index + 1] = color
            pixels[index + 2] = color
            pixels[index + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        // Mitad de tamaño: grano fino en pantallas Retina.
        return NSImage(cgImage: image, size: NSSize(width: size / 2, height: size / 2))
    }()
}

/// Botón de la barra (iconos de navegación, acciones): fondo al pasar el ratón, se encoge al pulsar.
public struct ChromeButtonStyle: ButtonStyle {
    var size: CGFloat

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        ChromeButton(configuration: configuration, size: size)
    }

    private struct ChromeButton: View {
        let configuration: Configuration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.spaceTheme) private var theme
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? Color(theme.title).opacity(0.85) : Color(theme.subtitle).opacity(0.6))
                .frame(minWidth: size, minHeight: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(theme.hover))
                        .opacity(isHovering && isEnabled ? 1 : 0)
                )
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .animation(Theme.pressSpring, value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering }
                }
        }
    }
}

/// Fila de la barra lateral: hover con el color del tema, selección con sombra y pulsación.
public struct SidebarRowStyle: ButtonStyle {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        SidebarRow(configuration: configuration, isSelected: isSelected)
    }

    private struct SidebarRow: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.spaceTheme) private var theme
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.rowHeight)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .fill(Color(theme.hover))
                            .opacity(isHovering && !isSelected ? 1 : 0)
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .fill(Color(theme.focus))
                            .overlay(
                                // Filo de luz arriba: da volumen a la pestaña seleccionada.
                                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(colors: [.white.opacity(0.14), .clear],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .opacity(isSelected ? 1 : 0)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .animation(Theme.pressSpring, value: configuration.isPressed)
                .animation(Theme.spring, value: isSelected)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering }
                }
                .environment(\.rowIsHovering, isHovering)
        }
    }
}

private struct RowIsHoveringKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Si el ratón está sobre la fila (para mostrar el botón de cerrar).
    var rowIsHovering: Bool {
        get { self[RowIsHoveringKey.self] }
        set { self[RowIsHoveringKey.self] = newValue }
    }
}
