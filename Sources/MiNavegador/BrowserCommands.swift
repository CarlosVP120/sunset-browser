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
            Button("Reabrir pestaña cerrada") { browser.reopenLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(browser.archive.isEmpty)
            Divider()
            Button("Nueva carpeta") { browser.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Cerrar pestaña") { browser.closeSelectedTab() }
                .keyboardShortcut("w")
        }

        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .pasteboard) {
            Button("Copiar URL") {
                guard let url = browser.selectedTab?.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandGroup(before: .sidebar) {
            Button(browser.showsSidebar ? "Ocultar barra lateral" : "Mostrar barra lateral") {
                withAnimation(.easeInOut(duration: 0.2)) { browser.showsSidebar.toggle() }
            }
            .keyboardShortcut("s")
            Button(browser.showsToolbar ? "Ocultar barra de herramientas" : "Mostrar barra de herramientas") {
                browser.showsToolbar.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("Navegación") {
            Button("Atrás") { browser.selectedTab?.goBack() }
                .keyboardShortcut("[")
            Button("Adelante") { browser.selectedTab?.goForward() }
                .keyboardShortcut("]")
            Button("Recargar") { browser.selectedTab?.reload() }
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
