import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI
import SidebarFeature
import ToolbarFeature

struct BrowserWindow: View {
    let browser: Browser

    var body: some View {
        HStack(spacing: 0) {
            if browser.showsSidebar {
                SidebarView(browser: browser)
                    .frame(width: Theme.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                if browser.showsToolbar {
                    ToolbarView(browser: browser)
                        .environment(\.colorScheme, .dark)
                }

                WebContentArea(browser: browser)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .padding(.top, browser.showsToolbar ? 0 : 6)
                    .padding(.leading, browser.showsSidebar ? 0 : 6)
                    .padding([.trailing, .bottom], 6)
            }
        }
        .background(SpaceBackground(color: browser.activeSpace.color))
        .background(WindowConfigurator())
        .ignoresSafeArea()
    }
}

private struct WebContentArea: View {
    let browser: Browser

    var body: some View {
        if let tab = browser.selectedTab {
            if let page = tab.page {
                WebContentView(page: page)
            } else {
                // Pestaña hibernada: se despierta al mostrarse.
                Color.white.task(id: tab.id) { tab.wake() }
            }
        } else {
            EmptyTabView(browser: browser)
        }
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

/// Ventana transparente para que se vea el vidrio, y arrastrable desde el fondo.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private struct EmptyTabView: View {
    let browser: Browser

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Ninguna pestaña abierta")
                .font(.title3.weight(.medium))
            Button("Nueva pestaña  ⌘T") { browser.newTab() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
