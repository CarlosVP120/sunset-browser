import SwiftUI
import BrowserCore

/// La dirección de la página. Al hacer clic abre el Command Bar sobre la pestaña actual, como en Arc.
public struct AddressButton: View {
    public enum Style {
        /// En la barra superior: icono del sitio aparte y dominio en una píldora que se ajusta al texto.
        case toolbar
        /// Como campo en la barra lateral (cuando la barra superior está oculta).
        case sidebar
    }

    let browser: Browser
    let style: Style
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, style: Style) {
        self.browser = browser
        self.style = style
    }

    public var body: some View {
        switch style {
        case .toolbar:
            HStack(spacing: 2) {
                if let url = browser.selectedTab?.url {
                    SiteInfoButton(browser: browser, url: url)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                Button { browser.editCurrentTab() } label: {
                    domainText(size: 13.5)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                }
                .buttonStyle(PillButtonStyle())
            }
            .animation(Theme.spring, value: browser.selectedTab?.url?.host())
            .tooltip("Buscar o escribir una URL", shortcut: "⌘L")

        case .sidebar:
            Button { browser.editCurrentTab() } label: {
                HStack(spacing: 6) {
                    if let url = browser.selectedTab?.url {
                        Image(systemName: url.scheme == "https" ? "lock.fill" : "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(theme.subtitle).opacity(1.4))
                    }
                    domainText(size: 13)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(PillButtonStyle(restingOpacity: 0.55, cornerRadius: Theme.cornerRadius))
            .tooltip("Buscar o escribir una URL", shortcut: "⌘L")
        }
    }

    private func domainText(size: CGFloat) -> some View {
        Group {
            if let url = browser.selectedTab?.url {
                Text(Self.displayHost(url))
                    .foregroundStyle(Color(theme.title))
            } else {
                Text("Buscar o escribir una URL")
                    .foregroundStyle(Color(theme.subtitle).opacity(1.4))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .lineLimit(1)
    }

    public static func displayHost(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Píldora neutra: aparece al pasar el ratón, se oscurece y encoge un poco al pulsar.
public struct PillButtonStyle: ButtonStyle {
    var restingOpacity: Double
    var cornerRadius: CGFloat

    public init(restingOpacity: Double = 0, cornerRadius: CGFloat = 7) {
        self.restingOpacity = restingOpacity
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, restingOpacity: restingOpacity, cornerRadius: cornerRadius)
    }

    private struct Pill: View {
        let configuration: Configuration
        let restingOpacity: Double
        let cornerRadius: CGFloat
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.11))
                        .opacity(isHovering || configuration.isPressed ? 1 : restingOpacity)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.pressSpring, value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering }
                }
        }
    }
}

/// Icono a la izquierda de la dirección: candado o enlace. Abre la información del sitio.
private struct SiteInfoButton: View {
    let browser: Browser
    let url: URL
    @State private var showsInfo = false
    @Environment(\.spaceTheme) private var theme

    var body: some View {
        let isSecure = url.scheme == "https"

        Button { showsInfo.toggle() } label: {
            Image(systemName: isSecure ? "lock" : "link")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(ChromeButtonStyle(size: 24))
        .tooltip("Información del sitio")
        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    FaviconView(pageURL: url, size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AddressButton.displayHost(url)).font(.headline)
                        Label(isSecure ? "Conexión segura" : "Conexión no segura",
                              systemImage: isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(isSecure ? Color.secondary : Color.orange)
                    }
                }
                Divider()
                HStack {
                    Button("Copiar enlace") {
                        browser.perform(.copyURL)
                        showsInfo = false
                    }
                    Spacer()
                    if let zoom = browser.selectedTab?.page?.zoom, zoom != 1 {
                        Button("Zoom \(Int((zoom * 100).rounded())) % · Restablecer") { browser.resetZoom() }
                    }
                }
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}
