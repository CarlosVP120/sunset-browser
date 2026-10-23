import AppKit
import BrowserCore
import BrowserEngine

/// Navegadores desde los que se puede migrar a Sunset.
public enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case arc, chrome, safari, brave, edge

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .arc: "Arc"
        case .chrome: "Google Chrome"
        case .safari: "Safari"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .arc: "company.thebrowser.Browser"
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    /// Icono de la app instalada.
    @MainActor
    public var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Color de la tarjeta (como en la bienvenida de Arc, cada navegador con el suyo).
    public var tint: SpaceColor {
        switch self {
        case .arc: SpaceColor(red: 0.98, green: 0.82, blue: 0.84)
        case .chrome: SpaceColor(red: 0.85, green: 0.92, blue: 1.0)
        case .safari: SpaceColor(red: 0.84, green: 0.91, blue: 0.99)
        case .brave: SpaceColor(red: 1.0, green: 0.78, blue: 0.68)
        case .edge: SpaceColor(red: 0.80, green: 0.93, blue: 0.95)
        }
    }

    /// Hay datos suyos en este Mac.
    public var isAvailable: Bool {
        if self == .safari { return true }
        return chromium.map { !$0.profiles().isEmpty } ?? false
    }

    /// Lo que se puede traer de este navegador.
    public var supportedKinds: ImportKinds {
        self == .arc ? .all : [.bookmarks, .history, .passwords, .cookies]
    }

    var chromium: ChromiumBrowser? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return switch self {
        case .arc: ChromiumBrowser(userDataDirectory: support.appending(path: "Arc/User Data"), keychainService: "Arc Safe Storage")
        case .chrome: ChromiumBrowser(userDataDirectory: support.appending(path: "Google/Chrome"), keychainService: "Chrome Safe Storage")
        case .brave: ChromiumBrowser(userDataDirectory: support.appending(path: "BraveSoftware/Brave-Browser"), keychainService: "Brave Safe Storage")
        case .edge: ChromiumBrowser(userDataDirectory: support.appending(path: "Microsoft Edge"), keychainService: "Microsoft Edge Safe Storage")
        case .safari: nil
        }
    }

    /// Navegadores con datos en este Mac, en el orden en que se ofrecen.
    public static var available: [ImportSource] { allCases.filter(\.isAvailable) }
}

/// Migra datos de otro navegador a Sunset. Solo lee del otro navegador (sobre copias):
/// allí no se borra ni se cambia nada.
public enum BrowserImporter {
    /// Lee los datos (fuera del hilo principal: las bases de datos pueden ser grandes).
    /// `passwordFile` es el CSV exportado (obligatorio para las contraseñas de Safari).
    public static func read(_ source: ImportSource, kinds: ImportKinds, passwordFile: URL? = nil) async -> ImportedData {
        await Task.detached(priority: .userInitiated) {
            readSync(source, kinds: kinds.intersection(source.supportedKinds), passwordFile: passwordFile)
        }.value
    }

    static func readSync(_ source: ImportSource, kinds: ImportKinds, passwordFile: URL?) -> ImportedData {
        var data = ImportedData()

        func problem(for error: Error) -> ImportProblem {
            switch error {
            case SQLiteReader.ReadError.permissionDenied: .needsFullDiskAccess
            case ChromiumCrypto.KeyError.denied: .keychainDenied
            default: .unavailable
            }
        }

        if source == .arc, kinds.contains(.sidebar) {
            do { data.sidebar = try ArcImporter.load() } catch { data.problems[.sidebar] = .unavailable }
        }

        if let chromium = source.chromium {
            let profiles = chromium.profiles().map(\.folder)
            let readers = profiles.map { ChromiumReader(browser: chromium, profile: $0) }

            if kinds.contains(.bookmarks), let reader = readers.first {
                do { data.bookmarks = try reader.bookmarks() } catch { data.problems[.bookmarks] = problem(for: error) }
            }
            if kinds.contains(.history) {
                data.history = readers.flatMap { (try? $0.history()) ?? [] }
                if data.history.isEmpty { data.problems[.history] = .unavailable }
            }
            // Contraseñas y cookies van cifradas: macOS pregunta si Sunset puede usar la clave.
            if !kinds.isDisjoint(with: [.passwords, .cookies]) {
                do {
                    let key = try ChromiumCrypto.storageKey(service: chromium.keychainService)
                    if kinds.contains(.passwords) {
                        data.credentials = readers.flatMap { (try? $0.credentials(key: key)) ?? [] }
                    }
                    if kinds.contains(.cookies), let reader = readers.first {
                        do { data.cookies = try reader.cookies(key: key) } catch { data.problems[.cookies] = problem(for: error) }
                    }
                } catch {
                    let issue = problem(for: error)
                    if kinds.contains(.passwords) { data.problems[.passwords] = issue }
                    if kinds.contains(.cookies) { data.problems[.cookies] = issue }
                }
            }
            if kinds.contains(.passwords), let passwordFile {
                data.credentials += credentials(fromCSV: passwordFile)
            }
        } else {
            let safari = SafariReader()
            if kinds.contains(.bookmarks) {
                do { data.bookmarks = try safari.bookmarks() } catch { data.problems[.bookmarks] = problem(for: error) }
            }
            if kinds.contains(.history) {
                do { data.history = try safari.history() } catch { data.problems[.history] = problem(for: error) }
            }
            if kinds.contains(.cookies) {
                do { data.cookies = try safari.cookies() } catch { data.problems[.cookies] = problem(for: error) }
            }
            if kinds.contains(.passwords) {
                if let passwordFile {
                    data.credentials = credentials(fromCSV: passwordFile)
                } else {
                    data.problems[.passwords] = .needsPasswordExport
                }
            }
        }
        return data
    }

    static func credentials(fromCSV file: URL) -> [Credential] {
        let accessing = file.startAccessingSecurityScopedResource()
        defer { if accessing { file.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return PasswordCSV.parse(text)
    }

    /// Guarda en Sunset lo leído.
    @MainActor
    public static func apply(_ data: ImportedData, from source: ImportSource, to browser: Browser,
                             passwords: PasswordVault) async -> ImportSummary {
        var summary = ImportSummary()
        summary.problems = data.problems

        if let sidebar = data.sidebar {
            browser.mergeSidebar(sidebar)
            summary.spaces = sidebar.spaces.count
            summary.tabs = sidebar.favorites.count + sidebar.spaces.reduce(0) { total, space in
                total + space.tabs.count + space.pinned.reduce(0) { count, item in
                    switch item {
                    case .tab: count + 1
                    case .folder(let folder): count + folder.tabs.count
                    }
                }
            }
        }
        if data.bookmarks.count > 0 {
            browser.addImportedSpace(
                named: source == .arc ? "Marcadores de Arc" : source.name,
                icon: "bookmark",
                color: SpaceColor.palette[browser.spaces.count % SpaceColor.palette.count],
                pinned: data.bookmarks.loose.map { ($0.title, $0.url) },
                folders: data.bookmarks.folders.map { folder in (folder.name, folder.bookmarks.map { ($0.title, $0.url) }) }
            )
            summary.bookmarks = data.bookmarks.count
        }
        if !data.history.isEmpty {
            browser.history.merge(data.history)
            summary.history = data.history.count
        }
        if !data.credentials.isEmpty {
            do {
                try passwords.add(data.credentials)
                summary.passwords = data.credentials.count
            } catch {
                summary.problems[.passwords] = .keychainDenied
            }
        }
        if !data.cookies.isEmpty {
            await browser.importCookies(data.cookies)
            summary.cookies = data.cookies.count
        }
        browser.saveNow()
        return summary
    }
}
