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
