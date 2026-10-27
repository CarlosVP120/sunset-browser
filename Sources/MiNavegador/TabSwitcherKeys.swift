import AppKit
import BrowserCore

/// ⌃Tab y ⌃⇧Tab como en Arc: recorren las pestañas por uso reciente mientras se mantiene ⌃, y al
/// soltarlo se abre la resaltada. El selector aparece si ⌃ sigue pulsado un instante; un ⌃Tab
/// rápido vuelve a la pestaña anterior sin enseñarlo. Con el selector abierto, ← → también mueven,
/// Intro abre y Esc cancela.
@MainActor
enum TabSwitcherKeys {
    private static var monitor: Any?
    private static var showTask: Task<Void, Never>?
    /// Tiempo con ⌃ pulsado antes de mostrar el selector.
    private static let showDelay: Duration = .milliseconds(160)

    private enum Key {
        static let tab: UInt16 = 48, escape: UInt16 = 53, returnKey: UInt16 = 36, enter: UInt16 = 76
        static let left: UInt16 = 123, right: UInt16 = 124
    }

    static func start(browser: Browser) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.type == .flagsChanged {
                // Soltar ⌃ abre la pestaña resaltada.
                if browser.tabSwitcher != nil, !flags.contains(.control) { finish { browser.commitTabSwitcher() } }
                return event
            }

            if event.keyCode == Key.tab, flags.subtracting(.shift) == .control {
                let isOpening = browser.tabSwitcher == nil
                browser.advanceTabSwitcher(backwards: flags.contains(.shift))
                if isOpening, browser.tabSwitcher != nil {
                    showTask = Task {
                        try? await Task.sleep(for: showDelay)
                        guard !Task.isCancelled else { return }
                        browser.showTabSwitcher()
                    }
                } else {
                    // Seguir pulsando Tab es pedir el selector: se muestra ya.
                    browser.showTabSwitcher()
                }
                return nil
            }

            guard browser.tabSwitcher != nil else { return event }
            switch event.keyCode {
            case Key.escape: finish { browser.cancelTabSwitcher() }
            case Key.returnKey, Key.enter: finish { browser.commitTabSwitcher() }
            case Key.right: browser.advanceTabSwitcher()
            case Key.left: browser.advanceTabSwitcher(backwards: true)
            default: break
            }
            // Mientras está abierto, el teclado es suyo (no llega a la página).
            return nil
        }
    }

    private static func finish(_ action: () -> Void) {
        showTask?.cancel()
        showTask = nil
        action()
    }
}
