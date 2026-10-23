import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI
import SidebarFeature
import ToolbarFeature
import CommandBarFeature
import ExtensionsFeature
import LibraryFeature
import HomeFeature
import OnboardingFeature

struct BrowserWindow: View {
    let browser: Browser
    let engine: WebKitEngine
    /// Barra lateral flotante al acercar el ratón al borde izquierdo con la barra oculta.
    @State private var isPeekingSidebar = false
    @State private var isResizingSidebar = false
    /// Dónde está la página en la ventana (para no poner vidrio debajo).
    @State private var contentFrame: CGRect = .zero
    private static let windowSpace = "browser-window"
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        // Los temas en modo "Automático" siguen el modo claro/oscuro del sistema.
        let theme = browser.activeSpace.theme.resolved(systemIsDark: systemColorScheme == .dark)

        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if browser.showsSidebar && browser.showsLibrary {
                    // La Librería ocupa el lugar de la barra lateral, algo más ancha.
                    LibraryView(browser: browser, downloads: engine.downloads, passwords: engine.passwords)
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

                    // Para que el scroll vaya fluido, la página no se recorta ni se le pone sombra desde
                    // SwiftUI (obligaría a recomponerla en cada fotograma): las esquinas van en su propia
                    // capa (ver WebContentView) y la sombra se dibuja aparte, detrás.
                    WebContentArea(browser: browser)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Color(white: 0.12))
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        )
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ContentFrameKey.self,
                                                   value: proxy.frame(in: .named(Self.windowSpace)))
                        })
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

            if let request = browser.welcome {
                OnboardingHost(browser: browser, passwords: engine.passwords, request: request)
                    .id(request)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(30)
            }

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
        // Un único receptor de clic derecho para los menús contextuales de toda la ventana.
        .overlay { ContextMenuCatcher() }
        .coordinateSpace(name: Self.windowSpace)
        .onPreferenceChange(ContentFrameKey.self) { contentFrame = $0 }
        .environment(\.spaceTheme, theme)
        // Vidrio solo alrededor de la página (las esquinas redondeadas quedan sobre vidrio).
        .background(SpaceBackground(theme: theme, opaqueRegion: contentFrame.insetBy(dx: Theme.cornerRadius,
                                                                                      dy: Theme.cornerRadius)))
        .background(WindowConfigurator())
        .onAppear { AnimationBenchmark.startIfRequested(browser: browser) }
        .ignoresSafeArea()
        .animation(Theme.spring, value: browser.showsSidebar)
        .animation(Theme.spring, value: browser.showsToolbar)
        .animation(Theme.spring, value: browser.showsLibrary)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: browser.commandBar)
        .animation(.easeInOut(duration: 0.45), value: browser.welcome)
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
        ZStack {
            // Páginas con vídeo en PiP (o sonando): siguen dentro de la ventana, invisibles detrás.
            // WebKit lo necesita para "volver a la pestaña" desde el PiP y para buscar en el vídeo.
            ParkedPagesView(pages: browser.parkedMediaPages)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        if let tab = browser.selectedTab, !tab.isHome {
            if let page = tab.page {
                VStack(spacing: 0) {
                    if let width = browser.responsiveWidth, tab.isDeveloperMode {
                        ResponsiveFrame(width: width) {
                            WebContentView(page: page, cornerRadius: Theme.cornerRadius)
                        }
                    } else {
                        WebContentView(page: page, cornerRadius: Theme.cornerRadius)
                    }
                }
                .animation(Theme.spring, value: browser.responsiveWidth)
            } else {
                // Pestaña hibernada: se despierta al mostrarse.
                Color.white.clipShape(shape).task(id: tab.id) { tab.wake() }
            }
        } else {
            // La pestaña Inicio, o ninguna pestaña abierta.
            HomeView(browser: browser)
                .clipShape(shape)
                .transition(.opacity)
        }
    }
}

/// Mantiene en la ventana, transparentes, las páginas de pestañas con vídeo que no se están viendo.
private struct ParkedPagesView: NSViewRepresentable {
    let pages: [WebPage]

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.alphaValue = 0
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let views = pages.map(\.view)
        for subview in container.subviews where !views.contains(where: { $0 === subview }) {
            subview.removeFromSuperview()
        }
        for view in views where view.superview !== container {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
    }
}

/// Muestra la vista nativa de la página (WKWebView hoy, Chromium mañana).
struct WebContentView: NSViewRepresentable {
    let page: WebPage
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        // Esquinas redondeadas en la capa: Core Animation las recorta sin dibujar la página de más.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
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

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// La bienvenida a pantalla completa sobre la ventana. Su estado vive aquí mientras se muestra.
private struct OnboardingHost: View {
    @State private var model: Onboarding

    init(browser: Browser, passwords: PasswordVault, request: WelcomeRequest) {
        _model = State(initialValue: Onboarding(
            browser: browser, passwords: passwords,
            startAt: request == .importOnly ? .importSource : .welcome,
            importOnly: request == .importOnly,
            onFinish: { browser.welcome = nil }
        ))
    }

    var body: some View {
        OnboardingView(model: model)
    }
}

/// Vista móvil del modo desarrollador: la página al ancho de un dispositivo, centrada, con su medida.
private struct ResponsiveFrame<Content: View>: View {
    let width: Double
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let shown = min(width, geometry.size.width - 32)
            VStack(spacing: 6) {
                Text("\(Int(shown)) × \(Int(geometry.size.height - 40)) px")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(height: 22)
                content
                    .frame(width: shown)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Color(white: 0.09))
            )
        }
    }
}
