import SwiftUI
import BrowserCore

/// Haz de luz ("tracing beam") que recorre el borde de la página mientras carga:
/// una línea fina de un solo color neutro con estela que se desvanece. Al terminar,
/// el haz se alarga hasta cerrar todo el borde y se apaga.
public struct PageEdgeGlow: View {
    let tab: BrowserTab?
    var cornerRadius: CGFloat

    @State private var startedAt: Date?
    @State private var finishedAt: Date?
    @State private var stopTask: Task<Void, Never>?
    @Environment(\.spaceTheme) private var theme

    /// Vueltas por segundo.
    private static let speed = 0.55
    /// Largo del haz, en fracción del borde.
    private static let beamLength = 0.2
    private static let slices = 16
    private static let finishDuration = 0.35
    private static let fadeDuration = 0.45

    public init(tab: BrowserTab?, cornerRadius: CGFloat = Theme.cornerRadius) {
        self.tab = tab
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        TimelineView(.animation(paused: startedAt == nil)) { context in
            if let startedAt {
                beam(at: context.date, startedAt: startedAt)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: tab?.isLoading, initial: true) { _, isLoading in update(isLoading: isLoading == true) }
        .onChange(of: tab?.id) {
            // Al cambiar de pestaña no se anima la salida: se muestra su estado tal cual.
            stopTask?.cancel()
            finishedAt = nil
            startedAt = tab?.isLoading == true ? Date() : nil
        }
    }

    private func beam(at now: Date, startedAt: Date) -> some View {
        let elapsed = now.timeIntervalSince(startedAt)
        let head = (elapsed * Self.speed).truncatingRemainder(dividingBy: 1)

        // Al terminar: el haz crece hasta rodear el borde y luego se apaga.
        var length = Self.beamLength
        var opacity = min(1, elapsed / 0.25)
        if let finishedAt {
            let finishing = now.timeIntervalSince(finishedAt)
            let grow = min(1, finishing / Self.finishDuration)
            length += (1 - Self.beamLength) * (1 - pow(1 - grow, 3))
            opacity *= 1 - min(1, max(0, finishing - Self.finishDuration * 0.8) / Self.fadeDuration)
        }

        let color = Color(theme.title)
        // Por fuera del borde de la página (inset negativo): sobre el marco de la ventana.
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: -1.5)

        return ZStack {
            // Rastro tenue de todo el borde.
            shape.stroke(color.opacity(0.12), lineWidth: 1)
            // El haz: tramos cada vez más brillantes hacia la cabeza.
            ForEach(0..<Self.slices, id: \.self) { slice in
                let sliceLength = length / Double(Self.slices)
                let end = head - length + sliceLength * Double(slice + 1)
                let strength = pow(Double(slice + 1) / Double(Self.slices), 2.2)
                ForEach(Self.segments(from: end - sliceLength, to: end), id: \.self) { segment in
                    shape.trim(from: segment.lowerBound, to: segment.upperBound)
                        .stroke(color.opacity(0.9 * strength), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            // Un destello pequeño en la cabeza.
            ForEach(Self.segments(from: head - 0.012, to: head), id: \.self) { segment in
                shape.trim(from: segment.lowerBound, to: segment.upperBound)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .blur(radius: 1.5)
            }
            .opacity(finishedAt == nil ? 1 : 0)
        }
        .opacity(opacity)
    }

    /// Un tramo del borde, partido en dos si cruza el punto de inicio.
    private static func segments(from start: Double, to end: Double) -> [ClosedRange<Double>] {
        guard end - start < 1 else { return [0...1] }
        let from = start - floor(start), to = end - floor(start)
        if to <= 1 { return [from...to] }
        return [from...1, 0...(to - 1)]
    }

    private func update(isLoading: Bool) {
        stopTask?.cancel()
        if isLoading {
            if startedAt == nil || finishedAt != nil { startedAt = Date() }
            finishedAt = nil
        } else if startedAt != nil, finishedAt == nil {
            finishedAt = Date()
            stopTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.finishDuration + Self.fadeDuration + 0.1))
                guard !Task.isCancelled else { return }
                startedAt = nil
                finishedAt = nil
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
