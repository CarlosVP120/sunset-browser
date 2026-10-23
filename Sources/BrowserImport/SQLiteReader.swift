import Foundation
import SQLite3

/// Lectura de las bases de datos SQLite de otros navegadores.
///
/// Nunca se abre el archivo original: se copia (con su diario WAL) a una carpeta temporal y se
/// lee la copia. Así no se bloquea ni se modifica nada del otro navegador, aunque esté abierto.
struct SQLiteReader {
    enum ReadError: Error {
        case notFound
        case permissionDenied
        case unreadable
    }

    typealias Row = [String: Value]

    enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case blob(Data)
        case null

        var int: Int64? {
            switch self {
            case .int(let value): value
            case .double(let value): Int64(value)
            case .text(let value): Int64(value)
            default: nil
            }
        }

        var double: Double? {
            switch self {
            case .double(let value): value
            case .int(let value): Double(value)
            default: nil
            }
        }

        var string: String? {
            switch self {
            case .text(let value): value
            case .blob(let value): String(data: value, encoding: .utf8)
            default: nil
            }
        }

        var data: Data? {
            switch self {
            case .blob(let value): value
            case .text(let value): Data(value.utf8)
            default: nil
            }
        }
    }

    /// Ejecuta una consulta de solo lectura sobre una copia del archivo.
    static func query(_ sql: String, in file: URL) throws -> [Row] {
        let copy = try temporaryCopy(of: file)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ReadError.unreadable
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ReadError.unreadable }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    row[name] = .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column), count > 0 {
                        row[name] = .blob(Data(bytes: bytes, count: count))
                    } else {
                        row[name] = .blob(Data())
                    }
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Copia la base de datos y sus archivos `-wal`/`-shm` a una carpeta temporal propia.
    private static func temporaryCopy(of file: URL) throws -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { throw ReadError.notFound }
        let folder = manager.temporaryDirectory.appending(path: "SunsetImport-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: file.lastPathComponent)
        do {
            try manager.copyItem(at: file, to: destination)
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            try? manager.removeItem(at: folder)
            throw ReadError.permissionDenied
        } catch {
            try? manager.removeItem(at: folder)
            throw isPermissionError(error) ? ReadError.permissionDenied : ReadError.unreadable
        }
        for suffix in ["-wal", "-shm"] {
            let companion = URL(fileURLWithPath: file.path + suffix)
            if manager.fileExists(atPath: companion.path) {
                try? manager.copyItem(at: companion, to: URL(fileURLWithPath: destination.path + suffix))
            }
        }
        return destination
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES)].contains(underlying.code) {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(nsError.code)
    }
}
