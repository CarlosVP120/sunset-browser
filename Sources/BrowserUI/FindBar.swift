import SwiftUI
import BrowserCore

/// Buscar en la página (⌘F): píldora flotante arriba a la derecha.
/// ↩ o ⌘G busca la siguiente coincidencia, ⇧↩ o ⇧⌘G la anterior, Esc cierra.
public struct FindBar: View {
    let browser: Browser
    @State private var text = ""
    @State private var found: Bool?
    @FocusState private var isFocused: Bool
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        ZStack {
            if browser.isFindBarVisible {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(theme.subtitle).opacity(1.5))
                    TextField("Buscar en la página", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(theme.title))
                        .frame(width: 190)
                        .focused($isFocused)
                        .onSubmit { search(direction: NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                        .onExitCommand { close() }
                    if found == false, !text.isEmpty {
                        Text("Sin resultados")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .transition(.opacity)
                    }
                    Button { search(direction: -1) } label: { Image(systemName: "chevron.up") }
                        .tooltip("Anterior", shortcut: "⇧⌘G")
                    Button { search(direction: 1) } label: { Image(systemName: "chevron.down") }
                        .tooltip("Siguiente", shortcut: "⌘G")
                    Button { close() } label: { Image(systemName: "xmark") }
                        .tooltip("Cerrar", shortcut: "⎋")
                }
                .buttonStyle(ChromeButtonStyle(size: 24))
                .disabled(false)
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(theme.background.first ?? .navy)).opacity(0.94)
                        .background(VisualEffectBlur(isDark: theme.isDark).clipShape(Capsule()))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                .environment(\.colorScheme, theme.isDark ? .dark : .light)
                .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                .onAppear { isFocused = true }
            }
        }
        .animation(Theme.spring, value: browser.isFindBarVisible)
        .animation(Theme.hoverOut, value: found)
        .onChange(of: browser.isFindBarVisible) { if browser.isFindBarVisible { isFocused = true } }
        .onChange(of: browser.findRequest) { search(direction: browser.findRequest.direction) }
        .task(id: text) {
            // Mientras escribes, busca desde el principio (con una pequeña pausa).
            guard !text.isEmpty else { found = nil; return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            search(direction: 1)
        }
    }

    private func search(direction: Int) {
        guard !text.isEmpty, direction != 0, let page = browser.selectedTab?.page else { return }
        let query = text
        Task {
            found = await page.find(query, backwards: direction < 0)
        }
    }

    private func close() {
        browser.isFindBarVisible = false
        found = nil
    }
}
