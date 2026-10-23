import SwiftUI
import BrowserCore
import BrowserUI

/// Barra superior (la opción "Show Toolbar" de Arc): navegación, dirección centrada y acciones.
public struct ToolbarView: View {
    let browser: Browser

    public init(browser: Browser) {
        self.browser = browser
    }

    public var body: some View {
        let tab = browser.selectedTab

        ZStack {
            HStack(spacing: 2) {
                if !browser.showsSidebar {
                    Button {
                        withAnimation(Theme.spring) { browser.showsSidebar = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Mostrar la barra lateral (⌘S)")
                    .transition(.opacity)
                }
                NavigationButtons(tab: tab)
                Spacer()
                Button { browser.perform(.copyURL) } label: {
                    Image(systemName: "link")
                }
                .disabled(tab?.url == nil)
                .help("Copiar enlace (⇧⌘C)")
            }
            .buttonStyle(ChromeButtonStyle())

            AddressButton(browser: browser, style: .toolbar)
                .frame(maxWidth: 460)
                .padding(.horizontal, 120)
        }
        .padding(.leading, browser.showsSidebar ? 2 : Theme.windowButtonsInset)
        .padding(.trailing, 6)
        .frame(height: Theme.toolbarHeight)
        .animation(Theme.spring, value: browser.showsSidebar)
    }
}
