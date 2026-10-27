import SwiftUI
import BrowserCore
import BrowserEngine
import BrowserUI
import OnboardingFeature

@main
struct MiNavegadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Una sola ventana: todas las pestañas viven en ella (abrir un enlace desde fuera
        // añade una pestaña, no una ventana nueva).
        Window("Sunset", id: "main") {
            BrowserWindow(browser: appDelegate.browser, engine: appDelegate.engine)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            BrowserCommands(browser: appDelegate.browser, engine: appDelegate.engine)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine: WebKitEngine
    let browser: Browser

    override init() {
        engine = WebKitEngine()
        // La primera vez no se importa nada por tu cuenta: la bienvenida te pregunta de dónde traer tus cosas.
        browser = Browser(engine: engine, importFromArc: false)
        super.init()

        if Onboarding.shouldShow(isFirstLaunch: browser.isFirstLaunch) {
            browser.welcome = .full
        }

        // Pausa las animaciones mientras haya un menú abierto (si no, el menú se congela).
        MenuTracking.start()

        // ⌘Z reabre la última pestaña cerrada.
        UndoCloseTab.start(browser: browser)

        // Iconos de sitios con contraseña HTTP o sesión: se piden desde la página abierta.
        engine.openTabForServiceWorker = { [browser] url in browser.openTab(url).wake() }
        FaviconCache.shared.sessionFetcher = { [engine] url in await engine.fetchWithPageSession(url) }

        engine.downloads.onFinish = { [browser] record in
            browser.showToast("Descargado: \(record.filename)", symbol: "arrow.down.circle.fill")
        }

        // Las extensiones ven las pestañas del navegador y pueden abrir nuevas.
        if #available(macOS 15.4, *) {
            let browser = browser
            engine.extensions.openTab = { url in browser.openTab(url).page }
            engine.extensions.orderedPages = { browser.allTabs.compactMap(\.page) }
            engine.extensions.onExtensionsLoaded = { browser.reloadExtensionPages() }
        }
    }

    /// Enlaces abiertos desde fuera, p. ej. `open -a MiNavegador https://apple.com`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            browser.openTab(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necesario cuando se ejecuta con `swift run` (sin bundle .app).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        browser.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
