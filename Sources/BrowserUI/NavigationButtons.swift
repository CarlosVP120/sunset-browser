import SwiftUI
import BrowserCore

/// Atrás, adelante y recargar.
public struct NavigationButtons: View {
    let tab: BrowserTab?

    public init(tab: BrowserTab?) {
        self.tab = tab
    }

    public var body: some View {
        HStack(spacing: 2) {
            Button { tab?.goBack() } label: { Image(systemName: "arrow.left") }
                .disabled(!(tab?.canGoBack ?? false))
                .help("Atrás")
            Button { tab?.goForward() } label: { Image(systemName: "arrow.right") }
                .disabled(!(tab?.canGoForward ?? false))
                .help("Adelante")
            Button {
                if tab?.isLoading == true { tab?.stopLoading() } else { tab?.reload() }
            } label: {
                Image(systemName: tab?.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .disabled(tab == nil)
            .help("Recargar")
        }
        .buttonStyle(ChromeButtonStyle())
    }
}
