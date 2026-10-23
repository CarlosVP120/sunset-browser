import Foundation

/// Cómo se abrió el Command Bar.
public enum CommandBarMode: Equatable, Sendable {
    /// ⌘T: lo que elijas se abre en una pestaña nueva.
    case newTab
    /// ⌘L: edita la pestaña actual.
    case currentTab
}

/// Dónde se suelta una pestaña arrastrada.
@MainActor
public enum DropLocation {
    case favorites(Int)
    case pinned(Int)
    case folder(Folder, Int)
    case today(Int)
}

/// Aviso de cambio de zoom; `id` cambia en cada ajuste para reiniciar la animación.
public struct ZoomIndicator: Equatable, Sendable {
    public let id = UUID()
    public let zoom: Double
}

/// Petición a la barra de búsqueda: siguiente (+1) o anterior (-1) coincidencia.
public struct FindRequest: Equatable, Sendable {
    public let id = UUID()
    public let direction: Int
}

/// Qué editor del espacio está abierto (desde su menú contextual).
public struct SpaceEditorRequest: Equatable, Sendable {
    public enum Kind: Sendable {
        case icon, rename, theme
    }

    public let spaceID: UUID
    public let kind: Kind

    public init(spaceID: UUID, kind: Kind) {
        self.spaceID = spaceID
        self.kind = kind
    }
}

/// Aviso breve que aparece y se va solo.
public struct Toast: Equatable, Sendable {
    public let id = UUID()
    public let message: String
    public let symbol: String
}
