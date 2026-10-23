import Foundation
import Observation
import BrowserEngine

/// Estado global del navegador: espacios, espacio activo y acciones sobre pestañas.
@MainActor
@Observable
public final class Browser {
    public private(set) var spaces: [Space]
    public var activeSpaceID: Space.ID
    /// Se incrementa para pedir a la interfaz que enfoque el campo de URL.
    public private(set) var urlFocusRequests = 0

    @ObservationIgnored private let engine: WebEngine

    public init(engine: WebEngine) {
        self.engine = engine
        let spaces = [
            Space(name: "Personal", icon: "house", hue: 0.62),
            Space(name: "Trabajo", icon: "briefcase", hue: 0.08),
        ]
        self.spaces = spaces
        activeSpaceID = spaces[0].id
    }

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    public var selectedTab: BrowserTab? { activeSpace.selectedTab }

    // MARK: - Pestañas

    @discardableResult
    public func openTab(_ url: URL? = nil, in space: Space? = nil) -> BrowserTab {
        let space = space ?? activeSpace
        let tab = BrowserTab(page: engine.makePage(), url: url)
        space.tabs.insert(tab, at: 0)
        space.selectedTabID = tab.id
        return tab
    }

    /// Abre una pestaña nueva y pide enfocar el campo de URL (Cmd+T).
    public func newTab() {
        openTab()
        requestURLFocus()
    }

    /// Navega en la pestaña actual o abre una si no hay ninguna.
    public func navigate(to input: String) {
        guard let url = URLInput.resolve(input) else { return }
        if let tab = selectedTab {
            tab.load(url)
        } else {
            openTab(url)
        }
    }

    public func select(_ tab: BrowserTab) {
        activeSpace.selectedTabID = tab.id
    }

    public func close(_ tab: BrowserTab) {
        let space = activeSpace
        let ordered = space.allTabs
        guard let index = ordered.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.page.stopLoading()
        space.pinnedTabs.removeAll { $0.id == tab.id }
        space.tabs.removeAll { $0.id == tab.id }
        if space.selectedTabID == tab.id {
            let remaining = space.allTabs
            space.selectedTabID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    public func closeSelectedTab() {
        if let tab = selectedTab { close(tab) }
    }

    public func togglePin(_ tab: BrowserTab) {
        let space = activeSpace
        if space.isPinned(tab) {
            space.pinnedTabs.removeAll { $0.id == tab.id }
            space.tabs.insert(tab, at: 0)
        } else {
            space.tabs.removeAll { $0.id == tab.id }
            space.pinnedTabs.append(tab)
        }
    }

    // MARK: - Espacios

    public func activate(_ space: Space) {
        activeSpaceID = space.id
    }

    public func addSpace(name: String) {
        let hue = Double(spaces.count) * 0.17
        let space = Space(name: name, icon: "circle.grid.2x2", hue: hue.truncatingRemainder(dividingBy: 1))
        spaces.append(space)
        activeSpaceID = space.id
    }

    public func requestURLFocus() {
        urlFocusRequests += 1
    }
}
