import XCTest
import CryptoKit
import SQLite3
@testable import BrowserImport
@testable import BrowserEngine
@testable import BrowserCore

final class ImportTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appending(path: "ImportTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Chromium

    func testChromiumCryptoRoundTrip() throws {
        let key = ChromiumCrypto.derivedKey(from: Data("peanuts".utf8))
        XCTAssertEqual(key.count, 16)
        let encrypted = try XCTUnwrap(ChromiumCrypto.encrypt(Data("s3cret!".utf8), key: key))
        XCTAssertEqual(encrypted.prefix(3), Data("v10".utf8))
        XCTAssertEqual(ChromiumCrypto.decrypt(encrypted, key: key), Data("s3cret!".utf8))
        XCTAssertNil(ChromiumCrypto.decrypt(Data("plain".utf8), key: key))
    }

    func testChromiumBookmarks() {
        let roots: [String: Any] = [
            "bookmark_bar": ["children": [
                ["type": "url", "name": "GitHub", "url": "https://github.com"],
                ["type": "folder", "name": "Trabajo", "children": [
                    ["type": "url", "name": "Jira", "url": "https://jira.example.com"],
                    ["type": "folder", "name": "Sub", "children": [["type": "url", "name": "Docs", "url": "https://docs.example.com"]]],
                ]],
                ["type": "url", "name": "Local", "url": "chrome://settings"],
            ]],
            "other": ["children": [["type": "url", "name": "Otro", "url": "https://otro.example.com"]]],
        ]
        let bookmarks = ChromiumReader.parseBookmarks(roots: roots)
        XCTAssertEqual(bookmarks.loose.map(\.title), ["GitHub"])
        XCTAssertEqual(bookmarks.folders.map(\.name), ["Trabajo", "Otros marcadores"])
        XCTAssertEqual(bookmarks.folders[0].bookmarks.map(\.title), ["Jira", "Docs"])
        XCTAssertEqual(bookmarks.count, 4)
    }

    func testChromiumProfileReadsHistoryPasswordsAndCookies() throws {
        let profile = folder.appending(path: "Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let key = ChromiumCrypto.derivedKey(from: Data("secret".utf8))
        // 13_380_000_000_000_000 µs desde 1601 ≈ año 2025.
        let visit: Int64 = 13_380_000_000_000_000
        let future: Int64 = 13_999_000_000_000_000

        try makeDatabase(profile.appending(path: "History"), [
            "CREATE TABLE urls (url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER, hidden INTEGER)",
            "INSERT INTO urls VALUES ('https://apple.com/', 'Apple', 7, \(visit), 0)",
            "INSERT INTO urls VALUES ('chrome://flags', 'Flags', 1, \(visit), 0)",
        ])
        let password = try XCTUnwrap(ChromiumCrypto.encrypt(Data("hunter2".utf8), key: key))
        try makeDatabase(profile.appending(path: "Login Data"), [
            "CREATE TABLE logins (origin_url TEXT, username_value TEXT, password_value BLOB, date_created INTEGER, blacklisted_by_user INTEGER)",
        ], blobs: ["INSERT INTO logins VALUES ('https://accounts.example.com/login', 'carlos', ?, \(visit), 0)": password])
        // Cookie de una base versión 24: el valor descifrado lleva delante 32 bytes de hash.
        let cookie = try XCTUnwrap(ChromiumCrypto.encrypt(Data(repeating: 7, count: 32) + Data("abc123".utf8), key: key))
        try makeDatabase(profile.appending(path: "Cookies"), [
            "CREATE TABLE meta (key TEXT, value TEXT)",
            "INSERT INTO meta VALUES ('version', '24')",
            """
            CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT,
              expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER)
            """,
            "INSERT INTO cookies VALUES ('.example.com', 'old', 'x', x'', '/', 1, 0, 0, 0)",
        ], blobs: ["INSERT INTO cookies VALUES ('.example.com', 'session', '', ?, '/', \(future), 1, 1, 1)": cookie])

        let reader = ChromiumReader(browser: ChromiumBrowser(userDataDirectory: folder, keychainService: "x"), profile: "Default")
        let history = try reader.history()
        XCTAssertEqual(history.map(\.title), ["Apple"])
        XCTAssertEqual(history.first?.visitCount, 7)

        let credentials = try reader.credentials(key: key)
        XCTAssertEqual(credentials.map(\.username), ["carlos"])
        XCTAssertEqual(credentials.first?.password, "hunter2")
        XCTAssertEqual(credentials.first?.host, "accounts.example.com")

        let cookies = try reader.cookies(key: key)
        XCTAssertEqual(cookies.map(\.name), ["session"]) // la caducada no se trae
        XCTAssertEqual(cookies.first?.value, "abc123")
        XCTAssertEqual(cookies.first?.isSecure, true)
        XCTAssertEqual(cookies.first?.isHTTPOnly, true)
    }

    // MARK: Safari

    func testSafariBookmarks() {
        let root: [String: Any] = ["Children": [
            ["Title": "History", "WebBookmarkType": "WebBookmarkTypeProxy"],
            ["Title": "BookmarksBar", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com", "URIDictionary": ["title": "Apple"]],
                ["WebBookmarkType": "WebBookmarkTypeList", "Title": "Noticias", "Children": [
                    ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://news.example.com", "URIDictionary": ["title": "News"]],
                ]],
            ]],
            ["Title": "BookmarksMenu", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://menu.example.com", "URIDictionary": ["title": "Menú"]],
            ]],
            ["Title": "com.apple.ReadingList", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://read.example.com", "URIDictionary": ["title": "Leer"]],
            ]],
        ]]
        let bookmarks = SafariReader.parseBookmarks(root: root)
        XCTAssertEqual(bookmarks.loose.map(\.title), ["Apple"])
        XCTAssertEqual(bookmarks.folders.map(\.name), ["Noticias", "Menú de marcadores", "Lista de lectura"])
    }

    func testBinaryCookies() throws {
        // Una página con una cookie, construida según el formato de Safari.
        func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        func le64(_ value: Double) -> [UInt8] { (0..<8).map { UInt8((value.bitPattern >> (8 * UInt64($0))) & 0xFF) } }
        let strings: [[UInt8]] = [Array(".example.com\0".utf8), Array("sid\0".utf8), Array("/\0".utf8), Array("xyz\0".utf8)]
        var offsets: [Int] = []
        var position = 56
        for string in strings { offsets.append(position); position += string.count }
        var cookie: [UInt8] = le32(position) + le32(0) + le32(1 | 4) + le32(0)
        cookie += offsets.flatMap(le32) + [UInt8](repeating: 0, count: 8)
        cookie += le64(Date().addingTimeInterval(86_400).timeIntervalSinceReferenceDate) + le64(0)
        cookie += strings.flatMap { $0 }
        let page: [UInt8] = [0, 0, 1, 0] + le32(1) + le32(16) + le32(0) + cookie
        func be32(_ value: Int) -> [UInt8] { (0..<4).reversed().map { UInt8((value >> (8 * $0)) & 0xFF) } }
        let file = Array("cook".utf8) + be32(1) + be32(page.count) + page

        let cookies = try BinaryCookies.parse(Data(file))
        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies.first?.domain, ".example.com")
        XCTAssertEqual(cookies.first?.name, "sid")
        XCTAssertEqual(cookies.first?.value, "xyz")
        XCTAssertEqual(cookies.first?.isSecure, true)
        XCTAssertEqual(cookies.first?.isHTTPOnly, true)
    }

    func testPasswordCSVFromApplePasswordsAndChrome() {
        let apple = """
        Title,URL,Username,Password,Notes,OTPAuth
        GitHub,https://github.com/,carlos,"pa,ss""word",,
        Sin URL,,x,y,,
        """
        let fromApple = PasswordCSV.parse(apple)
        XCTAssertEqual(fromApple.count, 1)
        XCTAssertEqual(fromApple.first?.password, "pa,ss\"word")
        XCTAssertEqual(fromApple.first?.host, "github.com")

        let chrome = "name,url,username,password,note\nX,x.com,yo,123,\n"
        XCTAssertEqual(PasswordCSV.parse(chrome).first?.url.absoluteString, "https://x.com")
    }

    // MARK: Contraseñas en Sunset

    @MainActor
    func testVaultEncryptsAndMerges() throws {
        let key = SymmetricKey(size: .bits256)
        let file = folder.appending(path: "Passwords.vault")
        let vault = PasswordVault(fileURL: file, keyProvider: { key })
        let url = URL(string: "https://www.example.com/login")!
        XCTAssertEqual(try vault.add([Credential(url: url, username: "ana", password: "1"),
                                      Credential(url: url, username: "ana", password: "2")]), 2)
        XCTAssertEqual(vault.credentials.count, 1)
        XCTAssertEqual(vault.credentials.first?.password, "2")

        // En disco no hay nada legible.
        let raw = try Data(contentsOf: file)
        XCTAssertNil(raw.range(of: Data("ana".utf8)))

        let reopened = PasswordVault(fileURL: file, keyProvider: { key })
        XCTAssertEqual(reopened.credentials(forHost: "login.example.com").map(\.username), ["ana"])
        XCTAssertEqual(reopened.credentials(forHost: "example.org"), [])

        let wrongKey = PasswordVault(fileURL: file, keyProvider: { SymmetricKey(size: .bits256) })
        XCTAssertThrowsError(try wrongKey.load())
    }

    func testCredentialSiteMatching() {
        let credential = Credential(url: URL(string: "https://accounts.google.com")!, username: "a", password: "b")
        XCTAssertTrue(credential.matches(host: "google.com"))
        XCTAssertTrue(credential.matches(host: "mail.google.com"))
        XCTAssertFalse(credential.matches(host: "google.com.evil.io"))
        let mexico = Credential(url: URL(string: "https://www.banco.com.mx")!, username: "a", password: "b")
        XCTAssertTrue(mexico.matches(host: "login.banco.com.mx"))
        XCTAssertFalse(mexico.matches(host: "otro.com.mx"))
    }

    // MARK: Aplicar en Sunset

    @MainActor
    func testApplyAddsBookmarksSpaceHistoryPasswordsAndCookies() async throws {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: nil, historyFileURL: nil, importFromArc: false,
                              defaults: UserDefaults(suiteName: UUID().uuidString)!, startsBackgroundWork: false)
        let vault = PasswordVault(fileURL: folder.appending(path: "v"), keyProvider: { SymmetricKey(data: Data(repeating: 1, count: 32)) })
        var data = ImportedData()
        data.bookmarks = ImportedBookmarks(
            loose: [ImportedBookmark(title: "Apple", url: URL(string: "https://apple.com")!)],
            folders: [ImportedFolder(name: "Dev", bookmarks: [ImportedBookmark(title: "GH", url: URL(string: "https://github.com")!)])]
        )
        data.history = [HistoryEntry(url: URL(string: "https://swift.org")!, title: "Swift", visitCount: 3, lastVisit: Date())]
        data.credentials = [Credential(url: URL(string: "https://github.com")!, username: "c", password: "p")]
        data.cookies = [HTTPCookie(properties: [.domain: "github.com", .name: "s", .value: "v", .path: "/"])!]

        let spacesBefore = browser.spaces.count
        let summary = await BrowserImporter.apply(data, from: .chrome, to: browser, passwords: vault)

        XCTAssertEqual(browser.spaces.count, spacesBefore + 1)
        XCTAssertEqual(browser.activeSpace.name, "Google Chrome")
        XCTAssertEqual(browser.activeSpace.pinned.count, 2)
        XCTAssertEqual(browser.history.entries.map(\.title), ["Swift"])
        XCTAssertEqual(vault.credentials.count, 1)
        XCTAssertEqual(engine.importedCookies.count, 1)
        XCTAssertEqual(summary.bookmarks, 2)
        XCTAssertEqual(summary.passwords, 1)
    }

    func testHistoryMergeAddsVisits() async {
        await MainActor.run {
            let history = History(fileURL: nil)
            let url = URL(string: "https://a.com")!
            history.record(url: url, title: "A", now: Date(timeIntervalSince1970: 0))
            let added = history.merge([
                HistoryEntry(url: url, title: "A", visitCount: 4, lastVisit: Date(timeIntervalSince1970: 100)),
                HistoryEntry(url: URL(string: "https://b.com")!, title: "B", visitCount: 1, lastVisit: Date()),
            ])
            XCTAssertEqual(added, 1)
            XCTAssertEqual(history.entries.first { $0.url == url }?.visitCount, 5)
        }
    }

    // MARK: Utilidades

    private func makeDatabase(_ file: URL, _ statements: [String], blobs: [String: Data] = [:]) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        for (sql, blob) in blobs {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK, sql)
            _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(blob.count), nil) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }
}
