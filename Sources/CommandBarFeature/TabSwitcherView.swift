import SwiftUI
import BrowserCore
import BrowserUI

/// El selector de ⌃Tab (como el de Arc): las pestañas recientes en fila, con su vista previa.
/// Se maneja con el teclado (ver `TabSwitcherKeys` en la app); también vale el ratón.
public struct TabSwitcherView: View {
    let browser: Browser
    let switcher: TabSwitcher
    /// La zona de la página: el panel se centra ahí, como el Command Bar.
    let area: CGRect?
    @Environment(\.spaceTheme) private var theme

    public init(browser: Browser, switcher: TabSwitcher, area: CGRect? = nil) {
        self.browser = browser
        self.switcher = switcher
        self.area = area
    }

    private static let spacing: CGFloat = 10
    private static let padding: CGFloat = 14

    public var body: some View {
        let tabs = switcher.tabIDs.compactMap { browser.tab(withID: $0) }
        GeometryReader { geometry in
            let zone = area.flatMap { $0.isEmpty ? nil : $0 } ?? CGRect(origin: .zero, size: geometry.size)
            // Tarjetas de 200 pt (más estrechas solo si la ventana es pequeña); si no caben todas,
            // la fila se desplaza siguiendo a la resaltada.
            let cardWidth = min(200, max(150, (zone.width - 80 - Self.padding * 2) / 3))
            // Solo tarjetas enteras a la vista (sin una cortada en el borde).
            let fits = Int((zone.width - 80 - Self.padding * 2 + Self.spacing) / (cardWidth + Self.spacing))
            let visible = CGFloat(max(1, min(tabs.count, fits)))
            let rowWidth = visible * cardWidth + (visible - 1) * Self.spacing
            ZStack {
                Color.black.opacity(0.001)
                    .onTapGesture { browser.cancelTabSwitcher() }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.spacing) {
                            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                TabSwitcherCard(tab: tab, preview: browser.tabPreviews[tab.id],
                                                isSelected: index == switcher.index, width: cardWidth)
                                    .id(index)
                                    .onHover { if $0 { browser.highlightTabSwitcher(index) } }
                                    .onTapGesture {
                                        browser.highlightTabSwitcher(index)
                                        browser.commitTabSwitcher()
                                    }
                            }
                        }
                        .padding(Self.padding)
                    }
                    .frame(width: rowWidth + Self.padding * 2)
                    .onChange(of: switcher.index) { proxy.scrollTo(switcher.index, anchor: .center) }
                    .onAppear { proxy.scrollTo(switcher.index, anchor: .center) }
                }
                .background(PanelBackground(theme: theme))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: zone.midX, y: zone.midY)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: switcher.index)
    }
}

private struct TabSwitcherCard: View {
    let tab: BrowserTab
    let preview: NSImage?
    let isSelected: Bool
    /// Ancho total de la tarjeta (con su margen).
    let width: CGFloat

    var body: some View {
        let width = self.width - 14
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Rectangle().fill(.white.opacity(0.06))
                if let preview {
                    // La parte de arriba de la página, que es la que se reconoce.
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: width, height: width * 0.625, alignment: .top)
                } else {
                    FaviconView(tab: tab, size: 34)
                }
            }
            .frame(width: width, height: width * 0.625)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))

            HStack(spacing: 7) {
                FaviconView(tab: tab, size: 14)
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 2)
            // El título se recorta: no puede ensanchar la tarjeta.
            .frame(width: width, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.16 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}
