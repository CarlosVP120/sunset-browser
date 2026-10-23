import Foundation
import Observation

/// Color en RGB (0–1), guardable en disco.
public struct SpaceColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let slate = SpaceColor(red: 0.20, green: 0.25, blue: 0.33)
    public static let plum = SpaceColor(red: 0.30, green: 0.20, blue: 0.32)
    public static let forest = SpaceColor(red: 0.16, green: 0.28, blue: 0.24)
    public static let ember = SpaceColor(red: 0.34, green: 0.20, blue: 0.16)
    public static let palette: [SpaceColor] = [.slate, .plum, .forest, .ember]
}

/// Una carpeta de pestañas fijadas.
@MainActor
@Observable
public final class Folder: Identifiable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool
    public internal(set) var tabs: [BrowserTab]

    init(id: UUID = UUID(), name: String, isExpanded: Bool = true, tabs: [BrowserTab] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.tabs = tabs
    }
}

/// Un elemento de la sección fijada: una pestaña o una carpeta.
@MainActor
public enum SidebarItem: Identifiable {
    case tab(BrowserTab)
    case folder(Folder)

    nonisolated public var id: UUID {
        switch self {
        case .tab(let tab): tab.id
        case .folder(let folder): folder.id
        }
    }
}

/// Un espacio: pestañas fijadas, pestañas de hoy, nombre, icono y color.
@MainActor
@Observable
public final class Space: Identifiable {
    public let id: UUID
    public var name: String
    /// Un SF Symbol o un emoji.
    public var icon: String
    public var color: SpaceColor

    public internal(set) var pinned: [SidebarItem] = []
    public internal(set) var tabs: [BrowserTab] = []
    public internal(set) var selectedTabID: BrowserTab.ID?

    init(id: UUID = UUID(), name: String, icon: String, color: SpaceColor) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }

    public var folders: [Folder] {
        pinned.compactMap { if case .folder(let folder) = $0 { folder } else { nil } }
    }

    /// Pestañas fijadas, incluidas las que están dentro de carpetas.
    public var pinnedTabs: [BrowserTab] {
        pinned.flatMap { item -> [BrowserTab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.tabs
            }
        }
    }

    public var allTabs: [BrowserTab] { pinnedTabs + tabs }

    public func isPinned(_ tab: BrowserTab) -> Bool {
        pinnedTabs.contains { $0.id == tab.id }
    }

    func remove(_ tab: BrowserTab) {
        tabs.removeAll { $0.id == tab.id }
        pinned.removeAll { if case .tab(let pinnedTab) = $0 { pinnedTab.id == tab.id } else { false } }
        for folder in folders {
            folder.tabs.removeAll { $0.id == tab.id }
        }
    }
}

/// Una pestaña cerrada, guardada en el archivo para poder recuperarla.
public struct ArchivedTab: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var title: String
    public var closedAt: Date
}
