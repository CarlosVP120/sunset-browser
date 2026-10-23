import SwiftUI
import BrowserCore
import BrowserEngine
import ExtensionsFeature

/// Menús y atajos de teclado, los mismos que Arc.
struct BrowserCommands: Commands {
    let browser: Browser
    let engine: WebKitEngine

    // Con Xcode 26 cada bloque admite como mucho 10 elementos: por eso los `Group`.
    var body: some Commands {
        Group {
            CommandGroup(replacing: .newItem) {
                Button("Nueva pestaña") { browser.newTab() }
                    .keyboardShortcut("t")
                Button("Nueva pestaña") { browser.newTab() }
                    .keyboardShortcut("n")
                Button("Abrir ubicación") { browser.editCurrentTab() }
                    .keyboardShortcut("l")
                Button("Inicio") { withAnimation { browser.openHome() } }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Reabrir pestaña cerrada") { browser.reopenLastClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(browser.archive.isEmpty)
                Group {
                    Divider()
                    Button("Nueva carpeta") { _ = browser.newFolder() }
                        .keyboardShortcut("n", modifiers: [.command, .option])
                    Button("Nuevo espacio") { browser.addSpace(name: "Espacio \(browser.spaces.count + 1)") }
                    Divider()
                    Button("Imprimir…") { browser.selectedTab?.page?.printPage() }
                        .keyboardShortcut("p")
                        .disabled(browser.selectedTab?.page == nil)
                    Divider()
                    Button("Cerrar pestaña") { browser.closeSelectedTab() }
                        .keyboardShortcut("w")
            }
        }

        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copiar URL") { browser.perform(.copyURL) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copiar URL como Markdown") { browser.perform(.copyURLAsMarkdown) }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Buscar en la página…") { browser.showFindBar() }
                .keyboardShortcut("f")
            Button("Buscar siguiente") { browser.findNext() }
                .keyboardShortcut("g")
            Button("Buscar anterior") { browser.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandGroup(before: .sidebar) {
            Button(browser.showsSidebar ? "Ocultar barra lateral" : "Mostrar barra lateral") {
                withAnimation(.easeInOut(duration: 0.2)) { browser.showsSidebar.toggle() }
            }
            .keyboardShortcut("s")
            Button(browser.showsLibrary ? "Cerrar la Librería" : "Abrir la Librería") {
                if browser.showsLibrary { browser.showsLibrary = false } else { browser.perform(.showLibrary) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Descargas") { browser.perform(.showDownloads) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button(browser.showsToolbar ? "Ocultar barra de herramientas" : "Mostrar barra de herramientas") {
                browser.showsToolbar.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
        }

        CommandGroup(after: .toolbar) {
            Button("Acercar") { browser.zoomIn() }
                .keyboardShortcut("+")
            Button("Acercar") { browser.zoomIn() }
                .keyboardShortcut("=")
            Button("Alejar") { browser.zoomOut() }
                .keyboardShortcut("-")
            Button("Tamaño real") { browser.resetZoom() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Atajos de teclado") { browser.showsShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
            Button("Mostrar la bienvenida") { browser.welcome = .full }
        }

        CommandGroup(after: .importExport) {
            Button("Importar de otro navegador…") { browser.welcome = .importOnly }
            Button("Volver a importar desde Arc") { try? browser.reimportFromArc() }
        }

        }
        Group {
            CommandMenu("Desarrollo") {
                Button("Modo desarrollador en este sitio") { browser.perform(.toggleDeveloperMode) }
                    // Como en Arc: Control (no Comando) + D, en cualquier sitio.
                    .keyboardShortcut("d", modifiers: .control)
                    .disabled(browser.selectedTab?.url == nil || browser.selectedTab?.isHome == true)
                Divider()
                Button("Consola") { browser.perform(.toggleConsole) }
                    .keyboardShortcut("j", modifiers: [.command, .option])
                    .disabled(browser.selectedTab?.isDeveloperMode != true)
                Button("Red") { browser.perform(.toggleNetwork) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(browser.selectedTab?.isDeveloperMode != true)
                Button("Inspeccionar elemento") { browser.perform(.inspectElement) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Inspector web") { browser.perform(.openWebInspector) }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Vista móvil") { browser.perform(.toggleResponsive) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(browser.selectedTab?.isDeveloperMode != true)
        }

        CommandMenu("Navegación") {
            Button("Atrás") { browser.selectedTab?.goBack() }
                .keyboardShortcut("[")
            Button("Adelante") { browser.selectedTab?.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Recargar") { browser.selectedTab?.reload() }
                .keyboardShortcut("r")
            Button("Recarga forzada") { browser.selectedTab?.reloadIgnoringCache() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Recarga forzada") { browser.selectedTab?.reloadIgnoringCache() }
                .keyboardShortcut("r", modifiers: [.control, .shift])
            Button("Imagen en imagen") { browser.perform(.pictureInPicture) }
                .keyboardShortcut("p", modifiers: [.command, .control])
            Toggle("Imagen en imagen automática", isOn: Binding(
                get: { browser.autoPictureInPicture },
                set: { browser.autoPictureInPicture = $0 }
            ))
            Group {
                Divider()
                Button("Detener") { browser.selectedTab?.stopLoading() }
                    .keyboardShortcut(".")
                    .disabled(browser.selectedTab?.isLoading != true)
                Divider()
                Button("Historial") { browser.newTab() }
                    .keyboardShortcut("y")
                Button("Buscar pestañas…") { browser.newTab() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        CommandMenu("Pestañas") {
            Button("Pestaña siguiente") { browser.selectAdjacentTab(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Pestaña anterior") { browser.selectAdjacentTab(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Pestaña siguiente") { browser.selectAdjacentTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Pestaña anterior") { browser.selectAdjacentTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Última pestaña usada") { browser.selectRecentTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Divider()
            ForEach(1..<9) { number in
                Button("Ir a la pestaña \(number)") { browser.selectTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")))
            }
            Group {
                Button("Ir a la última pestaña") { browser.selectLastTab() }
                    .keyboardShortcut("9")
                Divider()
                Button("Fijar / desfijar pestaña") {
                    if let tab = browser.selectedTab { browser.togglePin(tab) }
            }
            .keyboardShortcut("d")
            Button("Añadir a favoritos") {
                if let tab = browser.selectedTab { browser.addToFavorites(tab) }
            }
            }
        }

        CommandMenu("Espacios") {
            Button("Espacio siguiente") { browser.activateAdjacentSpace(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Espacio anterior") { browser.activateAdjacentSpace(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Editar color del tema…") {
                browser.spaceEditor = SpaceEditorRequest(spaceID: browser.activeSpaceID, kind: .theme)
            }
            Button("Renombrar espacio…") {
                browser.spaceEditor = SpaceEditorRequest(spaceID: browser.activeSpaceID, kind: .rename)
            }
            Button("Gestionar espacios…") { browser.showsSpaceManager = true }
            Divider()
            ForEach(Array(browser.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button(space.name) { browser.activate(space) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }

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
        }
    }
}
