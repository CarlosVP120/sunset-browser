import SwiftUI
import BrowserCore

/// Resplandor de carga al estilo Apple Intelligence: un gradiente de colores vivos que gira
/// por el borde de la página, con varias capas de desenfoque para dar profundidad y una
/// ligera "respiración". Al terminar la carga hace un destello breve y se desvanece.
public struct PageEdgeGlow: View {
    let tab: BrowserTab?
    var cornerRadius: CGFloat

    @State private var intensity: Double = 0
    @State private var flash: Double = 0
    @State private var isAnimating = false
    @State private var fadeTask: Task<Void, Never>?

    /// Paleta tipo Apple Intelligence: azul, morado, rosa, naranja y cian.
    private static let colors: [Color] = [
        Color(red: 0.18, green: 0.49, blue: 0.97),
        Color(red: 0.69, green: 0.32, blue: 0.87),
        Color(red: 1.00, green: 0.22, blue: 0.37),
        Color(red: 1.00, green: 0.62, blue: 0.04),
        Color(red: 0.35, green: 0.78, blue: 0.98),
        Color(red: 0.18, green: 0.49, blue: 0.97),
    ]

    public init(tab: BrowserTab?, cornerRadius: CGFloat = Theme.cornerRadius) {
        self.tab = tab
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = Angle.degrees(time.truncatingRemainder(dividingBy: 360 / 70) * 70)
            let breathing = 0.85 + 0.15 * sin(time * 2.6)

            ZStack {
                // Halo amplio y difuso hacia dentro.
                edge(lineWidth: 16, blur: 22, rotation: rotation + .degrees(40))
                    .opacity(0.45 * breathing)
                // Brillo medio.
                edge(lineWidth: 6, blur: 7, rotation: rotation)
                    .opacity(0.75 * breathing)
                // Filo nítido.
                edge(lineWidth: 1.6, blur: 0, rotation: rotation - .degrees(25))
                    .opacity(0.9)
                // Destello final: el filo se vuelve blanco un instante.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white, lineWidth: 2)
                    .blur(radius: 3)
                    .opacity(flash * 0.8)
            }
            .drawingGroup()
        }
        .opacity(intensity)
        .allowsHitTesting(false)
        .onChange(of: tab?.isLoading, initial: true) { _, isLoading in update(isLoading: isLoading == true) }
        .onChange(of: tab?.id) {
            // Al cambiar de pestaña no se anima: se muestra su estado tal cual.
            fadeTask?.cancel()
            let isLoading = tab?.isLoading == true
            intensity = isLoading ? 1 : 0
            flash = 0
            isAnimating = isLoading
        }
    }

    private func edge(lineWidth: CGFloat, blur: CGFloat, rotation: Angle) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(colors: Self.colors, center: .center, angle: rotation),
                lineWidth: lineWidth
            )
            .blur(radius: blur)
    }

    private func update(isLoading: Bool) {
        fadeTask?.cancel()
        if isLoading {
            isAnimating = true
            flash = 0
            withAnimation(.easeOut(duration: 0.45)) { intensity = 1 }
        } else if intensity > 0 {
            fadeTask = Task { @MainActor in
                withAnimation(.easeOut(duration: 0.14)) { flash = 1 }
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9)) {
                    flash = 0
                    intensity = 0
                }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                isAnimating = false
            }
        }
    }
}

/// Icono de pestaña con un anillo de progreso alrededor mientras carga.
public struct LoadingFavicon: View {
    let tab: BrowserTab
    var size: CGFloat
    @Environment(\.spaceTheme) private var theme

    public init(tab: BrowserTab, size: CGFloat = 16) {
        self.tab = tab
        self.size = size
    }

    public var body: some View {
        FaviconView(tab: tab, size: size)
            .scaleEffect(tab.isLoading ? 0.78 : 1)
            .overlay {
                if tab.isLoading {
                    ZStack {
                        Circle().stroke(Color(theme.title).opacity(0.15), lineWidth: 1.6)
                        Circle()
                            .trim(from: 0, to: max(0.08, tab.progress))
                            .stroke(Color(theme.accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Color(theme.accent).opacity(0.6), radius: 2)
                    }
                    .frame(width: size + 5, height: size + 5)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: tab.isLoading)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: tab.progress)
    }
}
