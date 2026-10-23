import AppKit
import SwiftUI
import BrowserCore
import BrowserUI

/// Menús contextuales de la barra lateral (los usan la lista nativa y los favoritos).
@MainActor
enum SidebarMenus {
    static func tab(_ tab: BrowserTab, browser: Browser) -> [MenuEntry] {
        let space = browser.activeSpace
        var entries: [MenuEntry] = [.button("Renombrar…") { browser.renamingTabID = tab.id }]
        if tab.customTitle != nil {
            entries.append(.button("Restablecer nombre") { browser.rename(tab, to: "") })
        }
        entries += [
            .button("Duplicar") {
                browser.select(tab)
                browser.perform(.duplicateTab)
            },
            .separator,
            .button("Añadir a favoritos") { browser.addToFavorites(tab) },
            .button(space.isPinned(tab) ? "Desfijar" : "Fijar") { browser.togglePin(tab) },
        ]
        if !space.folders.isEmpty {
            entries.append(.menu("Mover a carpeta", space.folders.map { folder in
                .button(folder.name) { browser.move(tab, to: .folder(folder, folder.tabs.count)) }
            }))
        }
        entries += [
            copyLink(tab),
            .separator,
            .button("Cerrar pestaña") { browser.close(tab) },
        ]
        return entries
    }

    static func folder(_ folder: Folder, browser: Browser, rename: @escaping @MainActor () -> Void) -> [MenuEntry] {
        [
            .button("Renombrar", action: rename),
            .button("Eliminar carpeta") { browser.delete(folder) },
        ]
    }

    static func copyLink(_ tab: BrowserTab) -> MenuEntry {
        .button("Copiar enlace", enabled: tab.url != nil) {
            guard let url = tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }
}
