import SwiftUI
import BrowserCore

/// Línea de luz que recorre el borde superior de la página mientras carga.
/// Sigue el progreso real, tiene una "cabeza" brillante y, al terminar, completa el
/// recorrido con un destello y se desvanece.
public struct PageLoadingBar: View {
    let tab: BrowserTab?
    @Environment(\.spaceTheme) private var theme

    @State private var shownProgress: Double = 0
    @State private var opacity: Double = 0
    @State private var flash: Double = 0
    @State private var finishTask: Task<Void, Never>?

    public init(tab: BrowserTab?) {
        self.tab = tab
    }

    public var body: some View {
        let accent = Color(theme.accent)

        GeometryReader { geometry in
            let width = geometry.size.width * shownProgress

            ZStack(alignment: .leading) {
                // Estela: se aclara hacia la cabeza.
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0), accent.opacity(0.8), accent, .white],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width, height: 2.5)
                    .shadow(color: accent.opacity(0.9), radius: 4)
                    .shadow(color: accent.opacity(0.5), radius: 10)

                // Cabeza brillante.
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .blur(radius: 2.5)
                    .shadow(color: accent, radius: 8)
                    .offset(x: max(width - 4, 0), y: -2.25)
                    .opacity(shownProgress < 1 ? 1 : 0)

                // Destello final a lo ancho.
                Rectangle()
                    .fill(LinearGradient(colors: [accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)
                    .opacity(flash)
            }
            .opacity(opacity)
        }
        .frame(height: 14, alignment: .top)
        .allowsHitTesting(false)
        .onChange(of: tab?.isLoading, initial: true) { _, isLoading in update(isLoading: isLoading == true) }
        .onChange(of: tab?.progress) { _, progress in
            guard tab?.isLoading == true, let progress else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                shownProgress = max(shownProgress, 0.08 + progress * 0.9)
            }
        }
        .onChange(of: tab?.id) {
            // Al cambiar de pestaña no se anima: se muestra su estado tal cual.
            finishTask?.cancel()
            let isLoading = tab?.isLoading == true
            shownProgress = isLoading ? 0.08 + (tab?.progress ?? 0) * 0.9 : 0
            opacity = isLoading ? 1 : 0
            flash = 0
        }
    }

    private func update(isLoading: Bool) {
        finishTask?.cancel()
        if isLoading {
            flash = 0
            if opacity == 0 { shownProgress = 0 }
            withAnimation(.easeOut(duration: 0.15)) { opacity = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                shownProgress = max(shownProgress, 0.08 + (tab?.progress ?? 0) * 0.9)
            }
        } else if opacity > 0 {
            finishTask = Task { @MainActor in
                withAnimation(.easeOut(duration: 0.22)) { shownProgress = 1 }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeOut(duration: 0.12)) { flash = 1 }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) {
                    flash = 0
                    opacity = 0
                }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                shownProgress = 0
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
