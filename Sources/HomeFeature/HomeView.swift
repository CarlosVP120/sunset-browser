import SwiftUI
import BrowserCore
import BrowserUI

/// La página Inicio: un punto de partida tranquilo y un lugar donde dejar el navegador en espera
/// (por ejemplo, al compartir pantalla). Reloj, saludo, buscador y favoritos sobre un fondo vivo.
public struct HomeView: View {
    let browser: Browser
    /// En modo pantalla compartida solo se ven el reloj y el buscador: nada personal.
    let isPresenting: Bool

    @State private var appeared = false
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, isPresenting: Bool = false) {
        self.browser = browser
        self.isPresenting = isPresenting
    }

    public var body: some View {
        let text = Color(theme.title)

        ZStack {
            HomeBackground(theme: theme)

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                Clock()
                    .foregroundStyle(text)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                Text(Self.greeting())
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(text.opacity(0.75))
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)

                SearchPill(browser: browser)
                    .frame(maxWidth: 560)
                    .padding(.top, 34)
                    .padding(.horizontal, 40)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.96)

                if !isPresenting && !browser.favorites.isEmpty {
                    FavoritesRow(browser: browser)
                        .padding(.top, 30)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .transition(.opacity)
                }

                Spacer(minLength: 40)

                PresentButton(browser: browser, isPresenting: isPresenting)
                    .padding(.bottom, 22)
            }
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .background {
            if isPresenting {
                // Esc sale del modo pantalla compartida.
                Button("") { withAnimation(Theme.spring) { browser.setPresenting(false) } }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) { appeared = true }
        }
    }

    /// "Buenos días, Carlos".
    static func greeting(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let salutation = switch hour {
        case 6..<12: "Buenos días"
        case 12..<20: "Buenas tardes"
        default: "Buenas noches"
        }
        let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? salutation : "\(salutation), \(firstName)"
    }
}

// MARK: - Reloj

private struct Clock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 112, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.9), value: context.date.formatted(.dateTime.minute()))
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .kerning(1.6)
                    .opacity(0.6)
            }
        }
    }
}

// MARK: - Buscador

/// Abre el Command Bar sobre esta pestaña: lo que busques se abre aquí mismo.
private struct SearchPill: View {
    let browser: Browser
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Button {
            browser.commandBar = browser.selectedTab?.isHome == true ? .currentTab : .newTab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                Text("Buscar o escribir una URL")
                    .font(.system(size: 17, weight: .medium))
                Spacer()
                ShortcutKeys("⌘L", onLightBackground: theme.isDark)
                    .opacity(0.7)
            }
            .foregroundStyle(Color(theme.title).opacity(0.7))
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(theme.hover).opacity(isHovering ? 0.9 : 0.4))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.22 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovering ? 0.25 : 0.15), radius: isHovering ? 22 : 14, y: 8)
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.spring) { isHovering = hovering } }
    }
}

// MARK: - Favoritos

private struct FavoritesRow: View {
    let browser: Browser

    var body: some View {
        HStack(spacing: 14) {
            ForEach(browser.favorites.prefix(8)) { tab in
                FavoriteLauncher(browser: browser, tab: tab)
            }
        }
    }

    private struct FavoriteLauncher: View {
        let browser: Browser
        let tab: BrowserTab
        @State private var isHovering = false
        @Environment(\.spaceTheme) private var theme

        var body: some View {
            Button { browser.select(tab) } label: {
                FaviconView(tab: tab, size: 26)
                    .frame(width: 62, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(theme.hover).opacity(isHovering ? 0.9 : 0.35))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isHovering ? 0.25 : 0.1), radius: isHovering ? 12 : 6, y: 4)
                    .scaleEffect(isHovering ? 1.08 : 1)
                    .offset(y: isHovering ? -3 : 0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in withAnimation(Theme.pressSpring) { isHovering = hovering } }
            .tooltip(tab.displayTitle)
        }
    }
}

// MARK: - Modo pantalla compartida

private struct PresentButton: View {
    let browser: Browser
    let isPresenting: Bool
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Button {
            withAnimation(Theme.spring) { browser.setPresenting(!isPresenting) }
        } label: {
            Label(isPresenting ? "Salir del modo pantalla compartida" : "Modo pantalla compartida",
                  systemImage: isPresenting ? "rectangle.on.rectangle" : "rectangle.on.rectangle.slash")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(theme.title).opacity(isHovering ? 0.9 : 0.55))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(Color(theme.hover)).opacity(isHovering ? 1 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.hoverIn) { isHovering = hovering } }
        .tooltip(isPresenting ? "Volver a tus pestañas" : "Oculta tus pestañas para compartir pantalla",
                 shortcut: isPresenting ? "⎋" : "⇧⌘P")
        // En modo presentación se nota menos hasta que pasas el ratón.
        .opacity(isPresenting && !isHovering ? 0.35 : 1)
    }
}
