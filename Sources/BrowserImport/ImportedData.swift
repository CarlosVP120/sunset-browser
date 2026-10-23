import Foundation
import BrowserCore
import BrowserEngine

/// Un marcador de otro navegador.
public struct ImportedBookmark: Equatable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// Una carpeta de marcadores (las subcarpetas se aplanan dentro de ella, como en la barra lateral).
public struct ImportedFolder: Equatable, Sendable {
    public var name: String
    public var bookmarks: [ImportedBookmark]

    public init(name: String, bookmarks: [ImportedBookmark]) {
        self.name = name
        self.bookmarks = bookmarks
    }
}

/// Todos los marcadores: los sueltos de la barra de favoritos y las carpetas.
public struct ImportedBookmarks: Equatable, Sendable {
    public var loose: [ImportedBookmark] = []
    public var folders: [ImportedFolder] = []

    public var count: Int { loose.count + folders.reduce(0) { $0 + $1.bookmarks.count } }

    public init(loose: [ImportedBookmark] = [], folders: [ImportedFolder] = []) {
        self.loose = loose
        self.folders = folders
    }
}

/// Qué se puede traer de otro navegador.
public struct ImportKinds: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Espacios, favoritos y pestañas fijadas (Arc).
    public static let sidebar = ImportKinds(rawValue: 1 << 0)
    public static let bookmarks = ImportKinds(rawValue: 1 << 1)
    public static let history = ImportKinds(rawValue: 1 << 2)
    public static let passwords = ImportKinds(rawValue: 1 << 3)
    /// Cookies: las sesiones abiertas (sigues con la sesión iniciada en tus sitios).
    public static let cookies = ImportKinds(rawValue: 1 << 4)

    public static let all: ImportKinds = [.sidebar, .bookmarks, .history, .passwords, .cookies]
}

/// Lo que se leyó del otro navegador, antes de guardarlo en Sunset.
public struct ImportedData: @unchecked Sendable {
    public var sidebar: SidebarSnapshot?
    public var bookmarks = ImportedBookmarks()
    public var history: [HistoryEntry] = []
    public var credentials: [Credential] = []
    public var cookies: [HTTPCookie] = []
    /// Lo que no se pudo leer y por qué (para explicarlo en el resumen).
    public var problems: [ImportKinds: ImportProblem] = [:]

    public init() {}
}

/// Por qué no se pudo leer algo.
public enum ImportProblem: Equatable, Sendable {
    /// macOS no deja leer la carpeta (Safari): hace falta "Acceso total al disco".
    case needsFullDiskAccess
    /// El usuario no permitió leer la clave del Llavero del otro navegador.
    case keychainDenied
    /// No hay datos de ese tipo, o el formato no se reconoce.
    case unavailable
    /// Safari no deja leer sus contraseñas: hay que exportarlas a un archivo CSV.
    case needsPasswordExport
}

/// Resumen de lo que se trajo, para mostrarlo al terminar.
public struct ImportSummary: Equatable, Sendable {
    public var spaces = 0
    public var tabs = 0
    public var bookmarks = 0
    public var history = 0
    public var passwords = 0
    public var cookies = 0
    public var problems: [ImportKinds: ImportProblem] = [:]

    public init() {}
}
