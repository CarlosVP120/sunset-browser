import Foundation
import BrowserCore
import BrowserEngine

/// Lee los datos de Safari. macOS protege su carpeta: hace falta "Acceso total al disco".
/// Las contraseñas de Safari viven en la app Contraseñas, que no deja leerlas: se importan desde
/// el archivo CSV que ella misma exporta (Archivo › Exportar todas las contraseñas).
struct SafariReader {
    var library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")

    private var safariFolder: URL { library.appending(path: "Safari") }

    // MARK: Marcadores

    func bookmarks() throws -> ImportedBookmarks {
        let file = safariFolder.appending(path: "Bookmarks.plist")
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw SQLiteReader.isPermissionError(error) ? SQLiteReader.ReadError.permissionDenied : SQLiteReader.ReadError.notFound
        }
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw SQLiteReader.ReadError.unreadable
        }
        return Self.parseBookmarks(root: root)
    }

    static func parseBookmarks(root: [String: Any]) -> ImportedBookmarks {
        func leaf(_ node: [String: Any]) -> ImportedBookmark? {
            guard node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
                  let string = node["URLString"] as? String, let url = URL(string: string),
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
            return ImportedBookmark(title: title ?? url.host() ?? string, url: url)
        }
        func flatten(_ node: [String: Any]) -> [ImportedBookmark] {
            (node["Children"] as? [[String: Any]] ?? []).flatMap { child in leaf(child).map { [$0] } ?? flatten(child) }
        }

        var result = ImportedBookmarks()
        for child in root["Children"] as? [[String: Any]] ?? [] {
            let title = child["Title"] as? String ?? ""
            switch title {
            case "BookmarksBar":
                // Favoritos de Safari: enlaces sueltos fijados y sus carpetas como carpetas.
                for item in child["Children"] as? [[String: Any]] ?? [] {
                    if let bookmark = leaf(item) {
                        result.loose.append(bookmark)
                    } else if item["WebBookmarkType"] as? String == "WebBookmarkTypeList" {
                        let bookmarks = flatten(item)
                        if !bookmarks.isEmpty {
                            result.folders.append(ImportedFolder(name: item["Title"] as? String ?? "Carpeta", bookmarks: bookmarks))
                        }
                    }
                }
            case "com.apple.ReadingList":
                let bookmarks = flatten(child)
                if !bookmarks.isEmpty { result.folders.append(ImportedFolder(name: "Lista de lectura", bookmarks: bookmarks)) }
            case "History", "":
                continue
            default:
                let bookmarks = flatten(child)
                let name = title == "BookmarksMenu" ? "Menú de marcadores" : title
                if !bookmarks.isEmpty { result.folders.append(ImportedFolder(name: name, bookmarks: bookmarks)) }
            }
        }
        if let loose = leaf(root) { result.loose.append(loose) }
        return result
    }

    // MARK: Historial

    func history(limit: Int = 5000) throws -> [HistoryEntry] {
        let rows = try SQLiteReader.query("""
            SELECT i.url AS url, i.visit_count AS visit_count, MAX(v.visit_time) AS last_visit,
                   (SELECT title FROM history_visits WHERE history_item = i.id AND title IS NOT NULL
                    ORDER BY visit_time DESC LIMIT 1) AS title
            FROM history_items i JOIN history_visits v ON v.history_item = i.id
            GROUP BY i.id ORDER BY last_visit DESC LIMIT \(limit)
            """, in: safariFolder.appending(path: "History.db"))
        return rows.compactMap { row in
            guard let string = row["url"]?.string, let url = URL(string: string),
                  url.scheme == "http" || url.scheme == "https" else { return nil }
            return HistoryEntry(url: url, title: row["title"]?.string ?? "",
                                visitCount: Int(row["visit_count"]?.int ?? 1),
                                lastVisit: Date(timeIntervalSinceReferenceDate: row["last_visit"]?.double ?? 0))
        }
    }

    // MARK: Cookies

    func cookies() throws -> [HTTPCookie] {
        let file = library.appending(path: "Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw SQLiteReader.isPermissionError(error) ? SQLiteReader.ReadError.permissionDenied : SQLiteReader.ReadError.notFound
        }
        return try BinaryCookies.parse(data)
    }
}

/// El formato `Cookies.binarycookies` de Safari.
enum BinaryCookies {
    static func parse(_ data: Data) throws -> [HTTPCookie] {
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes[0..<4] == [0x63, 0x6F, 0x6F, 0x6B] else { throw SQLiteReader.ReadError.unreadable } // "cook"

        func bigEndian(_ offset: Int) -> Int {
            guard offset + 4 <= bytes.count else { return 0 }
            return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        func littleEndian(_ offset: Int) -> Int {
            guard offset + 4 <= bytes.count else { return 0 }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        func double(_ offset: Int) -> Double {
            guard offset + 8 <= bytes.count else { return 0 }
            var raw: UInt64 = 0
            for (shift, byte) in bytes[offset..<offset + 8].enumerated() { raw |= UInt64(byte) << (8 * shift) }
            return Double(bitPattern: raw)
        }
        func string(_ offset: Int) -> String {
            guard offset < bytes.count else { return "" }
            let end = bytes[offset...].firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[offset..<end], as: UTF8.self)
        }

        let pageCount = bigEndian(4)
        var pageStart = 8 + pageCount * 4
        var cookies: [HTTPCookie] = []
        let now = Date()
        for page in 0..<pageCount {
            let pageSize = bigEndian(8 + page * 4)
            defer { pageStart += pageSize }
            guard pageStart + 8 <= bytes.count else { break }
            let count = littleEndian(pageStart + 4)
            for index in 0..<count {
                let start = pageStart + littleEndian(pageStart + 8 + index * 4)
                guard start + 56 <= bytes.count else { continue }
                let flags = littleEndian(start + 8)
                let domain = string(start + littleEndian(start + 16))
                let name = string(start + littleEndian(start + 20))
                let path = string(start + littleEndian(start + 24))
                let value = string(start + littleEndian(start + 28))
                let expires = Date(timeIntervalSinceReferenceDate: double(start + 40))
                guard !domain.isEmpty, !name.isEmpty, expires > now else { continue }
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .domain: domain, .name: name, .value: value, .path: path.isEmpty ? "/" : path, .expires: expires,
                ]
                if flags & 1 != 0 { properties[.secure] = "TRUE" }
                if flags & 4 != 0 { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
                if let cookie = HTTPCookie(properties: properties) { cookies.append(cookie) }
            }
        }
        return cookies
    }
}

/// Archivo CSV de contraseñas: el que exportan la app Contraseñas de Apple, Chrome, Arc, Firefox,
/// 1Password, Bitwarden… Se reconocen las columnas por su nombre.
public enum PasswordCSV {
    public static func parse(_ text: String) -> [Credential] {
        let rows = parseRows(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return [] }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlColumn = column(["url", "website", "login_uri", "web site", "origin"]),
              let passwordColumn = column(["password", "login_password"])
        else { return [] }
        let userColumn = column(["username", "user name", "login_username", "login", "email"])

        return rows.dropFirst().compactMap { row in
            guard row.count > max(urlColumn, passwordColumn) else { return nil }
            var urlText = row[urlColumn].trimmingCharacters(in: .whitespaces)
            if !urlText.contains("://") { urlText = "https://" + urlText }
            guard let url = URL(string: urlText), url.host() != nil, !row[passwordColumn].isEmpty else { return nil }
            let username = userColumn.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            return Credential(url: url, username: username, password: row[passwordColumn])
        }
    }

    /// CSV con comillas, comas y saltos de línea dentro de los campos.
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(character)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
