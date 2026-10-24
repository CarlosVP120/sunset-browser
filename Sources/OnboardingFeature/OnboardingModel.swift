import AppKit
import Observation
import BrowserCore
import BrowserEngine
import BrowserImport
import BrowserUI

/// Estado de la bienvenida: en qué paso estás y lo que has elegido.
@MainActor
@Observable
public final class Onboarding {
    public enum Step: Int, CaseIterable {
        case welcome, importSource, importKinds, importing, apps, theme, defaultBrowser, done
    }

    public private(set) var step: Step
    /// Para animar hacia delante o hacia atrás.
    private(set) var movingForward = true

    // Migración
    var source: ImportSource?
    var kinds: ImportKinds = .all
    var passwordFile: URL?
    private(set) var isImporting = false
    private(set) var summary: ImportSummary?
    let availableSources = ImportSource.available

    // Apps, tema y navegador predeterminado
    var selectedApps: Set<String> = []
    var colorIndex: Int?
    var appearance: SpaceTheme.Appearance = .auto
    var makeDefault: Bool?

    let browser: Browser
    let passwords: PasswordVault
    /// Abierta desde Archivo › Importar: al terminar de importar, se cierra.
    let importOnly: Bool
    private let onFinish: () -> Void

    private static let completedKey = "onboardingCompleted"

    public init(browser: Browser, passwords: PasswordVault, startAt step: Step = .welcome, importOnly: Bool = false,
                onFinish: @escaping () -> Void) {
        self.browser = browser
        self.passwords = passwords
        self.step = step
        self.importOnly = importOnly
        self.onFinish = onFinish
    }

    /// Hay que mostrarla: es la primera vez que se abre Sunset (o `SUNSET_ONBOARDING=1`).
    public static func shouldShow(isFirstLaunch: Bool, defaults: UserDefaults = .standard) -> Bool {
        if ProcessInfo.processInfo.environment["SUNSET_ONBOARDING"] == "1" { return true }
        return isFirstLaunch && !defaults.bool(forKey: completedKey)
    }

    // MARK: Navegación

    var canGoBack: Bool {
        if importOnly && step == .importSource { return false }
        return ![.welcome, .importing, .done].contains(step) && !isImporting
    }

    /// El paso se puede saltar ("Saltar por ahora").
    var isSkippable: Bool { [.apps, .theme, .defaultBrowser].contains(step) }

    var canContinue: Bool {
        switch step {
        case .importKinds: !kinds.intersection(source?.supportedKinds ?? []).isEmpty
        case .importing: !isImporting
        case .defaultBrowser: makeDefault != nil
        default: true
        }
    }

    var nextTitle: String {
        switch step {
        case .welcome: "Empezar"
        case .importSource where importOnly && source == nil: "Cerrar"
        case .importing where importOnly: "Listo"
        case .importKinds: "Traer a Sunset"
        case .done: "Empezar a navegar"
        default: "Siguiente"
        }
    }

    func next() {
        guard canContinue else { return }
        switch step {
        case .welcome: go(to: .importSource)
        case .importSource:
            if source == nil, importOnly { return finish() }
            go(to: source == nil ? .apps : .importKinds)
        case .importKinds:
            go(to: .importing)
            Task { await runImport() }
        case .importing:
            if importOnly { return finish() }
            go(to: .apps)
        case .apps:
            applyApps()
            go(to: .theme)
        case .theme:
            applyTheme()
            go(to: .defaultBrowser)
        case .defaultBrowser:
            if makeDefault == true { setAsDefaultBrowser() }
            go(to: .done)
        case .done: finish()
        }
    }

    func skip() {
        switch step {
        case .apps: go(to: .theme)
        case .theme: go(to: .defaultBrowser)
        case .defaultBrowser: go(to: .done)
        default: next()
        }
    }

    func back() {
        guard canGoBack else { return }
        let previous: Step = switch step {
        case .importSource: .welcome
        case .importKinds: .importSource
        case .apps: summary != nil ? .importing : .importSource
        case .theme: .apps
        case .defaultBrowser: .theme
        default: step
        }
        movingForward = false
        step = previous
    }

    private func go(to newStep: Step) {
        movingForward = true
        step = newStep
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish()
    }

    // MARK: Migración

    func choose(_ newSource: ImportSource?) {
        source = newSource
        kinds = newSource?.supportedKinds ?? []
        passwordFile = nil
    }

    func runImport() async {
        guard let source else { return }
        isImporting = true
        summary = nil
        let data = await BrowserImporter.read(source, kinds: kinds, passwordFile: passwordFile)
        summary = await BrowserImporter.apply(data, from: source, to: browser, passwords: passwords)
        isImporting = false
    }

    func retryImport() {
        Task { await runImport() }
    }

    /// Safari: el usuario elige el CSV exportado desde la app Contraseñas.
    func choosePasswordFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Elige el archivo que exportaste desde la app Contraseñas (Archivo › Exportar todas las contraseñas)."
        panel.prompt = "Usar este archivo"
        if panel.runModal() == .OK { passwordFile = panel.url }
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    func openPasswordsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// ¿Sunset puede leer la carpeta de Safari? (Hace falta "Acceso total al disco".)
    var canReadSafari: Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Bookmarks.plist")
        return FileManager.default.isReadableFile(atPath: file.path) && (try? Data(contentsOf: file)) != nil
    }

    // MARK: Apps favoritas

    struct App: Identifiable {
        let name: String
        let url: URL
        /// Icono del sitio. Gmail y Calendar comparten dominio con Google: sin el suyo, saldría la "G".
        let icon: URL?
        var id: String { name }
    }

    static let apps: [App] = [
        ("X", "https://x.com", nil),
        ("Gmail", "https://mail.google.com", "https://ssl.gstatic.com/ui/v1/icons/mail/images/favicon_gmail_2026_v2.ico"),
        ("Calendar", "https://calendar.google.com", "https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_31.ico"),
        ("YouTube", "https://www.youtube.com", nil), ("WhatsApp", "https://web.whatsapp.com", nil),
        ("Notion", "https://www.notion.so", nil), ("Slack", "https://app.slack.com", nil), ("Figma", "https://www.figma.com", nil),
        ("Spotify", "https://open.spotify.com", nil), ("ChatGPT", "https://chatgpt.com", nil),
        ("GitHub", "https://github.com", nil), ("Outlook", "https://outlook.live.com", nil),
    ].map { App(name: $0.0, url: URL(string: $0.1)!, icon: $0.2.flatMap(URL.init(string:))) }

    func toggle(_ app: App) {
        if selectedApps.contains(app.id) { selectedApps.remove(app.id) } else { selectedApps.insert(app.id) }
    }

    private func applyApps() {
        let chosen = Self.apps.filter { selectedApps.contains($0.id) }
        browser.addFavorites(chosen.map { ($0.name, $0.url) })
    }

    // MARK: Tema

    static let colors: [SpaceColor] = Array(SpaceTheme.presetSeeds.prefix(9).compactMap(\.first))

    var previewTheme: SpaceTheme {
        guard let colorIndex else { return browser.activeSpace.theme }
        let systemIsDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return .make(seeds: [Self.colors[colorIndex]], appearance: appearance, intensity: 0.5, grain: 0.35,
                     systemIsDark: systemIsDark)
    }

    private func applyTheme() {
        guard colorIndex != nil else { return }
        browser.setTheme(previewTheme, for: browser.activeSpace)
    }

    // MARK: Navegador predeterminado

    private func setAsDefaultBrowser() {
        // macOS muestra su propia confirmación ("¿Usar Sunset como navegador?").
        let app = Bundle.main.bundleURL
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
        }
    }
}
