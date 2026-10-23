import SwiftUI
import BrowserCore

/// Aviso breve abajo en el centro ("Enlace copiado"), como los de Arc. Se va solo.
public struct ToastView: View {
    let browser: Browser
    @State private var visible: Toast?

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        ZStack {
            if let toast = visible {
                HStack(spacing: 8) {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolEffect(.bounce, value: toast.id)
                    Text(toast.message)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(white: 0.1).opacity(0.94))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .id(toast.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.9)).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .animation(Theme.spring, value: visible)
        .allowsHitTesting(false)
        .task(id: browser.toast?.id) {
            guard let toast = browser.toast else { return }
            visible = toast
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { visible = nil }
        }
    }
}
