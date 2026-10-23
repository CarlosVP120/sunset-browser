import Foundation

/// Pedir la bienvenida: completa (primera vez) o solo el paso de importar otro navegador.
public enum WelcomeRequest: Equatable, Sendable {
    case full
    case importOnly
}

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

/// Secciones de la Librería.
public enum LibrarySection: String, CaseIterable, Sendable {
    case media, downloads, spaces, archive, passwords

    public var title: String {
        switch self {
        case .media: "Media"
        case .downloads: "Descargas"
        case .spaces: "Espacios"
        case .archive: "Pestañas archivadas"
        case .passwords: "Contraseñas"
        }
    }

    public var symbol: String {
        switch self {
        case .media: "photo.on.rectangle.angled"
        case .downloads: "arrow.down.circle"
        case .spaces: "square.stack"
        case .archive: "archivebox"
        case .passwords: "key"
        }
    }
}

/// La página Inicio: una pestaña propia del navegador (reloj, buscador, favoritos) en lugar de una web.
public enum HomePage {
    public static let url = URL(string: "minavegador://home")!

    public static func isHome(_ url: URL?) -> Bool {
        url?.scheme == "minavegador" && url?.host() == "home"
    }
}
