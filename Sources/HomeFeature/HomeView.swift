import SwiftUI
import BrowserCore
import BrowserUI

/// La página Inicio: un punto de partida tranquilo y un lugar donde dejar el navegador en espera
/// (por ejemplo, al compartir pantalla, para que no se vean tus páginas). Reloj, saludo, buscador y favoritos sobre un fondo vivo.
public struct HomeView: View {
    let browser: Browser

    @State private var appeared = false
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        ZStack {
            HomeBackground(theme: theme)

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                ZStack {
                    ForEach(0..<4, id: \.self) { ray in
                        SunsetLogo(ray: ray).fill(SunsetLogo.rayColors[ray])
                    }
                }
                    .frame(width: 38, height: 19)
                    .padding(.bottom, 22)
                    .opacity(appeared ? 0.95 : 0)
                    .scaleEffect(appeared ? 1 : 0.8)

                Clock()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                Text(Self.greeting())
                    .font(.system(size: 22, weight: .regular, design: .serif).italic())
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 14)
                    .opacity(appeared ? 1 : 0)

                SearchPill(browser: browser)
                    .frame(maxWidth: 560)
                    .padding(.top, 40)
                    .padding(.horizontal, 40)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.96)

                if !browser.favorites.isEmpty {
                    FavoritesRow(browser: browser)
                        .padding(.top, 28)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .transition(.opacity)
                }

                Spacer(minLength: 40)
            }
        }
        // El cielo de Inicio siempre es de noche: los controles van en modo oscuro.
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.05)) { appeared = true }
        }
    }

    /// "Buenos días, Alex".
    static func greeting(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let salutation = switch hour {
        case 6..<12: "Buenos días"
        case 12..<20: "Buenas tardes"
        default: "Buenas noches"
        }
        // `SUNSET_USER_NAME` cambia el nombre (para demos y capturas).
        let fullName = ProcessInfo.processInfo.environment["SUNSET_USER_NAME"] ?? NSFullUserName()
        let firstName = fullName.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? salutation : "\(salutation), \(firstName)"
    }
}

// MARK: - Reloj

private struct Clock: View {
    var body: some View {
        // Solo muestra horas y minutos: basta con despertar una vez por minuto.
        TimelineView(.everyMinute) { context in
            VStack(spacing: 10) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 12.5, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(2.6)
                    .foregroundStyle(.white.opacity(0.5))
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 104, weight: .ultraLight))
                    .kerning(-2)
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .white.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .white.opacity(0.12), radius: 30)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.9), value: context.date)
            }
        }
    }
}

// MARK: - Buscador

/// Abre el Command Bar sobre esta pestaña: lo que busques se abre aquí mismo.
private struct SearchPill: View {
    let browser: Browser
    @State private var isHovering = false

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
                ShortcutKeys("⌘L", onLightBackground: true)
                    .opacity(0.7)
            }
            .foregroundStyle(.white.opacity(isHovering ? 0.8 : 0.6))
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(isHovering ? 0.09 : 0.05))
                    )
            )
            .overlay(EdgeLight(cornerRadius: 18, isHovering: isHovering))
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

        var body: some View {
            Button { browser.select(tab) } label: {
                FaviconView(tab: tab, size: 26)
                    .frame(width: 62, height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(isHovering ? 0.1 : 0.04))
                            )
                    )
                    .overlay(EdgeLight(cornerRadius: 18, isHovering: isHovering))
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

/// Borde de vidrio: una línea de luz más clara arriba que abajo, como el canto de un cristal.
private struct EdgeLight: View {
    let cornerRadius: CGFloat
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(isHovering ? 0.32 : 0.2), .white.opacity(0.04), .white.opacity(isHovering ? 0.1 : 0.05)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
    }
}
