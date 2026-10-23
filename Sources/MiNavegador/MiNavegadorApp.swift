import SwiftUI
import BrowserCore
import BrowserEngine

@main
struct MiNavegadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Una sola ventana: todas las pestañas viven en ella (abrir un enlace desde fuera
        // añade una pestaña, no una ventana nueva).
        Window("MiNavegador", id: "main") {
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
        browser = Browser(engine: engine)
        super.init()

        // Las extensiones ven las pestañas del navegador y pueden abrir nuevas.
        if #available(macOS 15.4, *) {
            let browser = browser
            engine.extensions.openTab = { url in browser.openTab(url).page }
            engine.extensions.orderedPages = { browser.allTabs.compactMap(\.page) }
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
