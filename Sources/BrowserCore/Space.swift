import Foundation
import Observation

/// Un espacio: un conjunto de pestañas con su propio nombre, icono y color.
@MainActor
@Observable
public final class Space: Identifiable {
    public let id = UUID()
    public var name: String
    /// Nombre de un SF Symbol.
    public var icon: String
    /// Tono del color del espacio, de 0 a 1.
    public var hue: Double

    public internal(set) var pinnedTabs: [BrowserTab] = []
    public internal(set) var tabs: [BrowserTab] = []
    public var selectedTabID: BrowserTab.ID?

    public init(name: String, icon: String, hue: Double) {
        self.name = name
        self.icon = icon
        self.hue = hue
    }

    public var allTabs: [BrowserTab] { pinnedTabs + tabs }

    public var selectedTab: BrowserTab? {
        allTabs.first { $0.id == selectedTabID }
    }

    public func isPinned(_ tab: BrowserTab) -> Bool {
        pinnedTabs.contains { $0.id == tab.id }
    }
}
