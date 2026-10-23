import SwiftUI
import BrowserCore

/// Desenfoque nativo de macOS que deja ver lo que hay detrás de la ventana.
public struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    public init(material: NSVisualEffectView.Material = .hudWindow) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Fondo de la ventana: vidrio oscuro con un ligero tinte del color del espacio.
public struct SpaceBackground: View {
    let color: SpaceColor

    public init(color: SpaceColor) {
        self.color = color
    }

    public var body: some View {
        ZStack {
            VisualEffectBlur()
            LinearGradient(
                colors: [
                    Color(color).opacity(0.78),
                    Color(SpaceColor(red: color.red * 0.65, green: color.green * 0.65, blue: color.blue * 0.65))
                        .opacity(0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Brillo sutil arriba, como el reflejo de un vidrio.
            LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
        }
        .animation(.easeInOut(duration: 0.3), value: color)
    }
}

/// Botón de la barra (iconos de navegación, acciones): fondo solo al pasar el ratón.
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
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? Theme.primaryText.opacity(0.8) : Theme.secondaryText.opacity(0.5))
                .frame(minWidth: size, minHeight: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering && isEnabled ? Theme.hover : .clear)
                )
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}
