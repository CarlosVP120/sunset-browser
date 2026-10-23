import SwiftUI
import BrowserCore

/// Atajos de teclado del menú, como en Arc.
struct BrowserCommands: Commands {
    let browser: Browser

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva pestaña") { browser.newTab() }
                .keyboardShortcut("t")
            Button("Abrir ubicación") { browser.requestURLFocus() }
                .keyboardShortcut("l")
            Divider()
            Button("Cerrar pestaña") { browser.closeSelectedTab() }
                .keyboardShortcut("w")
        }

        CommandMenu("Navegación") {
            Button("Atrás") { browser.selectedTab?.page.goBack() }
                .keyboardShortcut("[")
            Button("Adelante") { browser.selectedTab?.page.goForward() }
                .keyboardShortcut("]")
            Button("Recargar") { browser.selectedTab?.page.reload() }
                .keyboardShortcut("r")
            Divider()
            Button("Fijar / desfijar pestaña") {
                if let tab = browser.selectedTab { browser.togglePin(tab) }
            }
            .keyboardShortcut("d")
        }

        CommandMenu("Espacios") {
            ForEach(Array(browser.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button(space.name) { browser.activate(space) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
    }
}
