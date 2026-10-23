import SwiftUI
import BrowserCore

/// La dirección de la página. Al hacer clic abre el Command Bar sobre la pestaña actual, como en Arc.
public struct AddressButton: View {
    public enum Style {
        /// Centrada en la barra superior.
        case toolbar
        /// Como campo en la barra lateral (cuando la barra superior está oculta).
        case sidebar
    }

    let browser: Browser
    let style: Style
    @Environment(\.spaceTheme) private var theme
    @State private var isHovering = false

    public init(browser: Browser, style: Style) {
        self.browser = browser
        self.style = style
    }

    public var body: some View {
        let url = browser.selectedTab?.url

        Button { browser.editCurrentTab() } label: {
            HStack(spacing: 6) {
                if let url {
                    Image(systemName: url.scheme == "https" ? "lock" : "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(theme.subtitle))
                    Text(Self.displayHost(url))
                        .lineLimit(1)
                        .foregroundStyle(Color(theme.title).opacity(0.9))
                } else {
                    Text("Buscar o escribir una URL")
                        .foregroundStyle(Color(theme.subtitle))
                }
            }
            .font(.system(size: style == .toolbar ? 12 : 12.5, weight: .medium))
            .frame(maxWidth: .infinity, alignment: style == .toolbar ? .center : .leading)
            .padding(.horizontal, 10)
            .frame(height: style == .toolbar ? 22 : 30)
            .background(
                RoundedRectangle(cornerRadius: style == .toolbar ? 6 : Theme.cornerRadius, style: .continuous)
                    .fill(Color(theme.hover))
                    .opacity(style == .sidebar ? (isHovering ? 1 : 0.6) : (isHovering ? 1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(hovering ? Theme.hoverIn : Theme.hoverOut) { isHovering = hovering }
        }
        .help("Buscar o escribir una URL (⌘L)")
    }

    public static func displayHost(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
