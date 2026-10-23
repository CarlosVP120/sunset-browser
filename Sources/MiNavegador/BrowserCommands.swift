import SwiftUI
import BrowserCore
import BrowserEngine
import ExtensionsFeature

/// Atajos de teclado del menú, como en Arc.
struct BrowserCommands: Commands {
    let browser: Browser
    let engine: WebKitEngine

    var body: some Commands {
        CommandMenu("Extensiones") {
            if #available(macOS 15.4, *) {
                let host = engine.extensions
                let storeID = WebExtensionsHost.chromeWebStoreID(from: browser.selectedTab?.url)
                Button("Añadir esta extensión desde Chrome Web Store") {
                    if let storeID { Task { await host.installFromChromeWebStore(id: storeID) } }
                }
                .disabled(storeID == nil)
                Button("Instalar desde archivo…") { ExtensionInstaller.chooseFile(host: host) }
                Divider()
                Button("Abrir Chrome Web Store") {
                    browser.openTab(URL(string: "https://chromewebstore.google.com/")!)
                }
            } else {
                Text("Las extensiones necesitan macOS 15.4 o posterior")
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Nueva pestaña") { browser.newTab() }
                .keyboardShortcut("t")
            Button("Abrir ubicación") { browser.editCurrentTab() }
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

        CommandGroup(after: .toolbar) {
            Button("Acercar") { browser.zoomIn() }
                .keyboardShortcut("+")
            Button("Alejar") { browser.zoomOut() }
                .keyboardShortcut("-")
            Button("Tamaño real") { browser.resetZoom() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(after: .importExport) {
            Button("Volver a importar desde Arc") { try? browser.reimportFromArc() }
        }

        CommandMenu("Navegación") {
            Button("Atrás") { browser.selectedTab?.goBack() }
                .keyboardShortcut("[")
            Button("Adelante") { browser.selectedTab?.goForward() }
                .keyboardShortcut("]")
            Button("Recargar") { browser.selectedTab?.reload() }
                .keyboardShortcut("r")
            Button("Detener") { browser.selectedTab?.stopLoading() }
                .keyboardShortcut(".")
                .disabled(browser.selectedTab?.isLoading != true)
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
