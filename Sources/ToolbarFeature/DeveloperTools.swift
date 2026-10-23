import SwiftUI
import AppKit
import BrowserCore
import BrowserEngine
import BrowserUI

// MARK: - Barra en modo desarrollador

public extension DeveloperMode {
    /// Amarillo de obra (el de Arc): el borde de las pestañas.
    static let color = Color(red: 1.0, green: 0.82, blue: 0.22)
}

/// Rayas diagonales de la barra en modo desarrollador (como en Arc): se nota de un vistazo
/// que estás en tu sitio local y no en producción.
struct DeveloperStripes: View {
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 14
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Color(theme.title).opacity(theme.isDark ? 0.07 : 0.06)), lineWidth: 5)
        }
        .allowsHitTesting(false)
    }
}

/// La dirección completa (con puerto y ruta), alineada a la izquierda y en monoespaciada.
struct DeveloperAddress: View {
    let browser: Browser
    let tab: BrowserTab
    @State private var isHovering = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button { browser.editCurrentTab() } label: {
                Text(tab.url?.absoluteString ?? "")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(theme.title).opacity(isHovering ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .tooltip("Editar dirección", shortcut: "⌘L")
        }
    }
}

/// Herramientas del modo desarrollador, a la derecha de la barra.
struct DeveloperToolbarButtons: View {
    let browser: Browser
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 2) {
            Button { browser.perform(.copyURL) } label: { Image(systemName: "link") }
                .tooltip("Copiar URL", shortcut: "⇧⌘C")

            Divider().frame(height: 16).padding(.horizontal, 4)

            Button { browser.perform(.forceReload) } label: { Image(systemName: "arrow.clockwise.circle") }
                .tooltip("Recarga forzada (sin caché)", shortcut: "⇧⌘R")
            Button { browser.perform(.capturePage) } label: { Image(systemName: "camera") }
                .tooltip("Capturar página")

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Un botón normal (con su hover) que abre el menú de tamaños.
            Button { NSMenu.popUpAtMouse(responsiveMenu) } label: {
                Image(systemName: browser.responsiveWidth == nil ? "iphone" : "iphone.gen3")
            }
            .background(Circle().fill(Color.primary.opacity(browser.responsiveWidth == nil ? 0 : 0.12)))
            .tooltip("Vista móvil", shortcut: "⇧⌘M")

            Button { browser.toggleInspector(.console) } label: {
                Image(systemName: "terminal")
                    .overlay(alignment: .topTrailing) {
                        if tab.console.unseenErrors > 0 {
                            Text("\(min(tab.console.unseenErrors, 99))")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3.5)
                                .frame(minWidth: 13, minHeight: 13)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 8, y: -7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .tooltip("Consola", shortcut: "⌥⌘J")

            // Como en Arc: el mundo muestra u oculta el panel de red.
            Button { browser.toggleInspector(.network) } label: { Image(systemName: "globe") }
                .tooltip("Panel de red", shortcut: "⌥⌘E")

            Button { browser.toggleInspector(.pickElement) } label: { Image(systemName: "scope") }
                .tooltip("Inspeccionar elemento", shortcut: "⌥⌘C")
        }
        .animation(Theme.pressSpring, value: tab.console.unseenErrors)
    }

    private var responsiveMenu: [MenuEntry] {
        let sizes: [(String, Double?)] = [("iPhone (390 px)", 390), ("iPhone Pro Max (430 px)", 430), ("iPad (820 px)", 820),
                                          ("Portátil (1280 px)", 1280), ("Ancho completo", nil)]
        return sizes.map { name, width in
            .button(name, checked: browser.responsiveWidth == width) {
                withAnimation(Theme.spring) { browser.responsiveWidth = width }
            }
        }
    }
}
