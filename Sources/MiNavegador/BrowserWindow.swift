import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI
import SidebarFeature
import ToolbarFeature
import CommandBarFeature
import ExtensionsFeature
import LibraryFeature

struct BrowserWindow: View {
    let browser: Browser
    let engine: WebKitEngine
    /// Barra lateral flotante al acercar el ratón al borde izquierdo con la barra oculta.
    @State private var isPeekingSidebar = false
    @State private var isResizingSidebar = false
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        // Los temas en modo "Automático" siguen el modo claro/oscuro del sistema.
        let theme = browser.activeSpace.theme.resolved(systemIsDark: systemColorScheme == .dark)

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if browser.showsSidebar && browser.showsLibrary {
                    // La Librería ocupa el lugar de la barra lateral, algo más ancha.
                    LibraryView(browser: browser, downloads: engine.downloads)
                        .frame(width: max(browser.sidebarWidth, 400))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                } else if browser.showsSidebar {
                    SidebarView(browser: browser, accessory: sidebarAccessory, libraryButton: libraryButton)
                        .frame(width: browser.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }

                VStack(spacing: 0) {
                    if browser.showsToolbar {
                        ToolbarView(browser: browser) { extensionsToolbar }
                            .environment(\.colorScheme, theme.isDark ? .dark : .light)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    WebContentArea(browser: browser)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .overlay { PageEdgeGlow(tab: browser.selectedTab) }
                        .overlay(alignment: .top) {
                            ZoomIndicatorView(browser: browser).padding(.top, 10)
                        }
                        .overlay(alignment: .topTrailing) {
                            FindBar(browser: browser).padding([.top, .trailing], 10)
                        }
                        .padding(.top, browser.showsToolbar ? 0 : 6)
                        .padding(.leading, browser.showsSidebar ? 0 : 6)
                        .padding([.trailing, .bottom], 6)
                }
            }

            // El borde para redimensionar vive fuera de la barra: así el arrastre sigue
            // aunque la barra se colapse a mitad del gesto.
            if (browser.showsSidebar && !browser.showsLibrary) || isResizingSidebar {
                SidebarResizeHandle(browser: browser, isResizing: $isResizingSidebar)
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .offset(x: (browser.showsSidebar ? browser.sidebarWidth : 0) - 5)
                    .zIndex(2)
            }

            if !browser.showsSidebar && !isResizingSidebar {
                peekingSidebar
            }

            ToastView(browser: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .zIndex(20)

            if let mode = browser.commandBar {
                CommandBarView(browser: browser, mode: mode)
                    .id(mode)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                    ))
                    .zIndex(10)
            }
        }
        .environment(\.spaceTheme, theme)
        .background(SpaceBackground(theme: theme))
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .animation(Theme.spring, value: browser.showsSidebar)
        .animation(Theme.spring, value: browser.showsToolbar)
        .animation(Theme.spring, value: browser.showsLibrary)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: browser.commandBar)
        .onChange(of: browser.showsSidebar) { isPeekingSidebar = false }
        .sheet(isPresented: Binding(
            get: { browser.showsSpaceManager },
            set: { browser.showsSpaceManager = $0 }
        )) {
            SpaceManagerView(browser: browser)
        }
        .sheet(isPresented: Binding(
            get: { browser.showsShortcuts },
            set: { browser.showsShortcuts = $0 }
        )) {
            ShortcutsView()
        }
    }

    @ViewBuilder
    private var extensionsToolbar: some View {
        if #available(macOS 15.4, *) {
            ExtensionsToolbar(browser: browser, host: engine.extensions)
        }
    }

    private var libraryButton: AnyView {
        AnyView(LibraryButton(browser: browser, downloads: engine.downloads))
    }

    /// Con la barra superior oculta, las extensiones van arriba en la barra lateral.
    private var sidebarAccessory: AnyView? {
        browser.showsToolbar ? nil : AnyView(extensionsToolbar)
    }

    @ViewBuilder
    private var peekingSidebar: some View {
        // Franja invisible en el borde: al tocarla aparece la barra lateral flotante.
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { if $0 { withAnimation(Theme.spring) { isPeekingSidebar = true } } }

        if isPeekingSidebar {
            SidebarView(browser: browser, accessory: sidebarAccessory, libraryButton: libraryButton)
                .frame(width: browser.sidebarWidth)
                .background(SpaceBackground(theme: browser.activeSpace.theme.resolved(systemIsDark: systemColorScheme == .dark)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, x: 6)
                .padding(.vertical, 6)
                .padding(.leading, 6)
                .onHover { if !$0 { withAnimation(Theme.spring) { isPeekingSidebar = false } } }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(5)
        }
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
