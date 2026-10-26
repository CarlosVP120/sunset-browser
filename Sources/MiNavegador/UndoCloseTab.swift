import AppKit
import WebKit
import BrowserCore

/// Como en Arc, ⌘Z vuelve a abrir la última pestaña cerrada (donde estaba). Si se está escribiendo,
/// en un campo de Sunset o de la página, ⌘Z sigue deshaciendo lo escrito.
@MainActor
enum UndoCloseTab {
    private static var monitor: Any?
    /// El ⌘Z que se devuelve a la página: no se vuelve a interceptar.
    private static var passingThrough = false

    static func start(browser: Browser) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !passingThrough,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "z",
                  let window = event.window, browser.canReopenClosedTab
            else { return event }

            // Un campo de texto de Sunset (Command Bar, renombrar…).
            if window.firstResponder is NSText { return event }
            guard let view = window.firstResponder as? NSView, isInWebView(view),
                  let page = browser.selectedTab?.page
            else {
                browser.reopenLastClosedTab()
                return nil
            }
            // En la página solo se sabe preguntándole: se decide y, si escribía, se le devuelve el ⌘Z.
            Task {
                if await page.isEditingText() {
                    passingThrough = true
                    NSApp.sendEvent(event)
                    passingThrough = false
                } else {
                    browser.reopenLastClosedTab()
                }
            }
            return nil
        }
    }

    private static func isInWebView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if view is WKWebView { return true }
            current = view.superview
        }
        return false
    }
}
