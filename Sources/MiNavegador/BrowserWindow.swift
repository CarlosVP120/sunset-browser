import SwiftUI
import BrowserCore
import BrowserEngine
import SidebarFeature

struct BrowserWindow: View {
    let browser: Browser

    var body: some View {
        let space = browser.activeSpace

        HStack(spacing: 0) {
            SidebarView(browser: browser)
                .frame(width: 260)

            Group {
                if let tab = browser.selectedTab {
                    WebContentView(page: tab.page)
                } else {
                    EmptyTabView(browser: browser)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .padding([.top, .bottom, .trailing], 8)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(hue: space.hue, saturation: 0.35, brightness: 0.95),
                    Color(hue: space.hue, saturation: 0.55, brightness: 0.80),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: browser.activeSpaceID)
    }
}

/// Muestra la vista nativa de la página (WKWebView hoy, Chromium mañana).
struct WebContentView: NSViewRepresentable {
    let page: WebPage

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard container.subviews.first !== page.view else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        page.view.frame = container.bounds
        page.view.autoresizingMask = [.width, .height]
        container.addSubview(page.view)
    }
}

private struct EmptyTabView: View {
    let browser: Browser

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No hay ninguna pestaña abierta")
                .font(.title3)
            Button("Nueva pestaña (⌘T)") { browser.newTab() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
