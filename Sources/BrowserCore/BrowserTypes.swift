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
