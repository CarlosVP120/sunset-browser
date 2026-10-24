import SwiftUI
import BrowserCore

/// Desenfoque nativo de macOS. Por defecto deja ver lo que hay detrás de la ventana (el escritorio);
/// con `.withinWindow`, lo que hay debajo dentro de la propia ventana (para paneles sobre la página).
public struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var isDark: Bool
    var blendingMode: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material = .hudWindow, isDark: Bool = true,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.isDark = isDark
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
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
    /// Zona tapada por la página (opaca). Ahí no se pone vidrio: el desenfoque del escritorio
    /// se recalcula al recomponer la ventana, y bajo una página que hace scroll a 120–180 Hz
    /// sería trabajo inútil en cada fotograma.
    let opaqueRegion: CGRect?

    public init(theme: SpaceTheme, opaqueRegion: CGRect? = nil) {
        self.theme = theme
        self.opaqueRegion = opaqueRegion
    }

    public var body: some View {
        ZStack {
            if let hole = opaqueRegion, hole.width > 0, hole.height > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(Self.glassRects(around: hole, in: geometry.size).enumerated()), id: \.offset) { _, rect in
                            VisualEffectBlur(isDark: theme.isDark)
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                        Color(theme.background.first ?? .navy)
                            .frame(width: hole.width, height: hole.height)
                            .offset(x: hole.minX, y: hole.minY)
                    }
                }
            } else {
                VisualEffectBlur(isDark: theme.isDark)
            }

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

    /// Las franjas de vidrio alrededor de la zona opaca: izquierda, derecha, arriba y abajo.
    static func glassRects(around hole: CGRect, in size: CGSize) -> [CGRect] {
        let overlap: CGFloat = 1
        return [
            CGRect(x: 0, y: 0, width: hole.minX + overlap, height: size.height),
            CGRect(x: hole.maxX - overlap, y: 0, width: size.width - hole.maxX + overlap, height: size.height),
            CGRect(x: hole.minX, y: 0, width: hole.width, height: hole.minY + overlap),
            CGRect(x: hole.minX, y: hole.maxY - overlap, width: hole.width, height: size.height - hole.maxY + overlap),
        ].filter { $0.width > 0 && $0.height > 0 }
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
    let height: CGFloat

    public init(isSelected: Bool, height: CGFloat = Theme.rowHeight) {
        self.isSelected = isSelected
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        SidebarRow(configuration: configuration, isSelected: isSelected, height: height)
    }

    private struct SidebarRow: View {
        let configuration: Configuration
        let isSelected: Bool
        let height: CGFloat
        @Environment(\.spaceTheme) private var theme
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                // Los fondos solo existen cuando se ven: con opacidad 0 igualmente se calculaban
                // (y la sombra se dibujaba) en cada fila y en cada fotograma de las animaciones.
                .background {
                    ZStack {
                        if isHovering && !isSelected {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Color(theme.hover))
                                .transition(.opacity)
                        }
                        if isSelected {
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
                            .transition(.opacity)
                        }
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
