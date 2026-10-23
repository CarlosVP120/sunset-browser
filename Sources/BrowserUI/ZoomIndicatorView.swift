import SwiftUI
import BrowserCore

/// Píldora flotante con el zoom actual y botones − / +, que se oculta sola (como en Arc).
public struct ZoomIndicatorView: View {
    let browser: Browser
    @State private var visibleIndicator: ZoomIndicator?
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        ZStack {
            if let indicator = visibleIndicator {
                HStack(spacing: 2) {
                    Button { browser.zoomOut() } label: { Image(systemName: "minus") }
                    Text("\(Int((indicator.zoom * 100).rounded())) %")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 46)
                        .contentTransition(.numericText(value: indicator.zoom))
                    Button { browser.zoomIn() } label: { Image(systemName: "plus") }
                    Divider().frame(height: 14).padding(.horizontal, 4)
                    Button("Restablecer") { browser.resetZoom() }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(ChromeButtonStyle(size: 24))
                .foregroundStyle(Color(theme.title))
                .padding(4)
                .background(
                    Capsule().fill(Color(theme.background.first ?? .navy)).opacity(0.92)
                        .background(VisualEffectBlur(isDark: theme.isDark).clipShape(Capsule()))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .onHover { isHovering = $0 }
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .animation(Theme.spring, value: visibleIndicator)
        .task(id: browser.zoomIndicator?.id) {
            guard let indicator = browser.zoomIndicator else { return }
            visibleIndicator = indicator
            // Se queda mientras el ratón está encima; si no, desaparece a los 1,5 s.
            repeat {
                try? await Task.sleep(for: .seconds(1.5))
            } while isHovering && !Task.isCancelled
            if !Task.isCancelled { visibleIndicator = nil }
        }
    }
}
