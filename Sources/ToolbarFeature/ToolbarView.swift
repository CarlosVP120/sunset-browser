import SwiftUI
import BrowserCore
import BrowserUI

/// Barra superior (la opción "Show Toolbar" de Arc): navegación, dirección centrada y,
/// a la derecha, lo que aporte la app (los botones de extensiones).
public struct ToolbarView<Trailing: View>: View {
    let browser: Browser
    let trailing: Trailing

    public init(browser: Browser, @ViewBuilder trailing: () -> Trailing) {
        self.browser = browser
        self.trailing = trailing()
    }

    public var body: some View {
        if let tab = browser.selectedTab, tab.isDeveloperMode, !tab.isHome {
            developerBody(tab)
        } else {
            standardBody
        }
    }

    /// Modo desarrollador (como Arc): rayas, la dirección completa a la izquierda y herramientas.
    private func developerBody(_ tab: BrowserTab) -> some View {
        HStack(spacing: 2) {
            if !browser.showsSidebar {
                Button {
                    withAnimation(Theme.spring) { browser.showsSidebar = true }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .tooltip("Mostrar barra lateral", shortcut: "⌘S")
            }
            NavigationButtons(tab: tab)
            DeveloperAddress(browser: browser, tab: tab)
                .padding(.leading, 6)
            DeveloperToolbarButtons(browser: browser, tab: tab)
            trailing
        }
        .buttonStyle(ChromeButtonStyle())
        .padding(.leading, browser.showsSidebar ? 2 : Theme.windowButtonsInset)
        .padding(.trailing, 6)
        .frame(height: Theme.toolbarHeight)
        .background(DeveloperStripes().padding(.vertical, -6))
        .transition(.opacity)
    }

    private var standardBody: some View {
        ZStack {
            HStack(spacing: 2) {
                if !browser.showsSidebar {
                    Button {
                        withAnimation(Theme.spring) { browser.showsSidebar = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .tooltip("Mostrar barra lateral", shortcut: "⌘S")
                    .transition(.opacity)
                }
                NavigationButtons(tab: browser.selectedTab)
                Spacer()
                trailing
            }
            .buttonStyle(ChromeButtonStyle())

            AddressButton(browser: browser, style: .toolbar)
                .fixedSize()
        }
        .padding(.leading, browser.showsSidebar ? 2 : Theme.windowButtonsInset)
        .padding(.trailing, 6)
        .frame(height: Theme.toolbarHeight)
        .animation(Theme.spring, value: browser.showsSidebar)
    }
}

public extension ToolbarView where Trailing == EmptyView {
    init(browser: Browser) {
        self.init(browser: browser) { EmptyView() }
    }
}
