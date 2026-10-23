import Foundation
import Observation

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
    public var theme: SpaceTheme
    /// Perfil del espacio (cookies y sesiones propias); `nil` es el predeterminado.
    public internal(set) var profileID: UUID?

    public internal(set) var pinned: [SidebarItem] = []
    public internal(set) var tabs: [BrowserTab] = []
    public internal(set) var selectedTabID: BrowserTab.ID?

    init(id: UUID = UUID(), name: String, icon: String, theme: SpaceTheme) {
        self.id = id
        self.name = name
        self.icon = icon
        self.theme = theme
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

/// Un perfil: cookies, sesiones y datos web separados (p. ej. "Trabajo" con otra cuenta de Google).
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
