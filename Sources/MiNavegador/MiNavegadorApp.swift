import SwiftUI
import BrowserCore
import BrowserEngine

@main
struct MiNavegadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            BrowserWindow(browser: appDelegate.browser)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            BrowserCommands(browser: appDelegate.browser)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let browser = Browser(engine: WebKitEngine())

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
