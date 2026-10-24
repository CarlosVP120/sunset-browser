import WebKit
import Observation

/// Una extensión instalada (se guarda en `Extensions.json`).
public struct InstalledExtension: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var version: String
    /// De dónde vino: `chrome-web-store:<id>` o el nombre del archivo.
    public var source: String
    public var isEnabled: Bool
}

/// Extensiones web (el mismo formato que las de Chrome, Manifest V2/V3) sobre WebKit.
/// Instala, carga y conecta las extensiones con las pestañas, la ventana y la barra.
@available(macOS 15.4, *)
@MainActor
@Observable
public final class WebExtensionsHost: NSObject {
    public private(set) var installed: [InstalledExtension] = []
    /// Se incrementa cuando cambia el icono, la insignia o el título de algún botón.
    public private(set) var actionsRevision = 0
    public private(set) var isInstalling = false
    public var lastError: String?

    @ObservationIgnored public let controller: WKWebExtensionController
    @ObservationIgnored private var contexts: [UUID: WKWebExtensionContext] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored let window = ExtensionWindow()
    @ObservationIgnored private var openPages: [WeakPage] = []
    @ObservationIgnored private weak var activePage: WebKitPage?

    // MARK: Conexión con el navegador (la configura la app)

    /// Abre una pestaña (para `chrome.tabs.create` y las páginas de opciones). Devuelve la página creada.
    @ObservationIgnored public var openTab: ((URL?) -> WebPage?)?
    /// Pestañas en el orden de la barra lateral.
    @ObservationIgnored public var orderedPages: (() -> [WebPage])?
    /// Dónde mostrar el popup de una extensión: vista y rectángulo del botón pulsado.
    @ObservationIgnored public var popupAnchor: [UUID: CGRect] = [:]

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "MiNavegador/Extensions")
        controller = WKWebExtensionController(configuration: .default())
        super.init()
        controller.delegate = self
        window.host = self
        loadRegistry()
        Task { await loadEnabledExtensions() }
    }

    // MARK: - Consultas para la interfaz

    public func context(for id: UUID) -> WKWebExtensionContext? {
        contexts[id]
    }

    /// El botón de la extensión para la pestaña visible.
    public func action(for id: UUID) -> WKWebExtension.Action? {
        contexts[id]?.action(for: activePage)
    }

    /// Funciones de Chrome que pide la extensión y Sunset no tiene (vacío si es compatible).
    public func unsupportedFeatures(for id: UUID) -> [String] {
        ExtensionCompatibility.unsupportedFeatures(inExtensionAt: folder(for: id))
    }

    /// La configuración para abrir una página de una extensión (`webkit-extension://<id>/…`):
    /// con la normal, WebKit responde "resource unavailable" y la pestaña queda en blanco.
    public func webViewConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard url.scheme == "webkit-extension" else { return nil }
        return contexts.values.first { $0.baseURL.host() == url.host() }?.webViewConfiguration
    }

    /// Pulsar el botón de la extensión (abre su popup o ejecuta su acción).
    public func performAction(for id: UUID, anchor: CGRect) {
        popupAnchor[id] = anchor
        contexts[id]?.performAction(for: activePage)
    }

    public func openOptions(for id: UUID) {
        guard let url = contexts[id]?.optionsPageURL else { return }
        _ = openTab?(url)
    }

    // MARK: - Instalar, activar, quitar

    /// Si la URL es la ficha de una extensión en Chrome Web Store, su identificador.
    nonisolated public static func chromeWebStoreID(from url: URL?) -> String? {
        guard let url, let host = url.host(),
              host == "chromewebstore.google.com" || host == "chrome.google.com" else { return nil }
        return url.pathComponents.last { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains($0) } }
    }

    /// Descarga e instala una extensión de Chrome Web Store (el mismo paquete .crx que usa Chrome).
    public func installFromChromeWebStore(id: String) async {
        let request = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0.0.0"
            + "&acceptformat=crx2,crx3&x=id%3D\(id)%26installsource%3Dondemand%26uc"
        guard let url = URL(string: request) else { return }
        isInstalling = true
        defer { isInstalling = false }
        do {
            let (file, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.downloadFailed }
            let crx = file.deletingPathExtension().appendingPathExtension("crx")
            try? FileManager.default.removeItem(at: crx)
            try FileManager.default.moveItem(at: file, to: crx)
            defer { try? FileManager.default.removeItem(at: crx) }
            try await install(from: crx, source: "chrome-web-store:\(id)")
        } catch {
            lastError = message(for: error)
        }
    }

    /// Instala desde una carpeta descomprimida, un .zip o un .crx.
    public func install(from fileURL: URL) async {
        isInstalling = true
        defer { isInstalling = false }
        do {
            try await install(from: fileURL, source: fileURL.lastPathComponent)
        } catch {
            lastError = message(for: error)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: UUID) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].isEnabled = enabled
        saveRegistry()
        if enabled {
            await load(installed[index])
        } else if let context = contexts.removeValue(forKey: id) {
            try? controller.unload(context)
        }
        actionsRevision += 1
    }

    public func uninstall(_ id: UUID) {
        if let context = contexts.removeValue(forKey: id) { try? controller.unload(context) }
        installed.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(for: id))
        saveRegistry()
        actionsRevision += 1
    }

    enum InstallError: LocalizedError {
        case downloadFailed, unsupportedFile, cancelled

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "No se pudo descargar la extensión."
            case .unsupportedFile: "El archivo no es una extensión válida (.crx, .zip o carpeta con manifest.json)."
            case .cancelled: nil
            }
        }
    }

    private func install(from fileURL: URL, source: String) async throws {
        let id = UUID()
        let destination = folder(for: id)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try unpack(fileURL, into: destination)
            let webExtension = try await WKWebExtension(resourceBaseURL: destination)

            // Como en Chrome: antes de instalar, se muestra lo que la extensión podrá hacer (y lo
            // que no va a poder hacer en Sunset).
            let unsupported = ExtensionCompatibility.unsupportedFeatures(inExtensionAt: destination)
            guard confirmInstall(webExtension, unsupported: unsupported) else { throw InstallError.cancelled }

            let record = InstalledExtension(
                id: id,
                name: webExtension.displayName ?? fileURL.deletingPathExtension().lastPathComponent,
                version: webExtension.displayVersion ?? webExtension.version ?? "",
                source: source,
                isEnabled: true
            )
            installed.append(record)
            saveRegistry()
            await load(record, granting: true)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Copia la carpeta o descomprime el .zip/.crx en `destination`.
    private func unpack(_ fileURL: URL, into destination: URL) throws {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &isDirectory)
        if isDirectory.boolValue {
            for item in try FileManager.default.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil) {
                try FileManager.default.copyItem(at: item, to: destination.appending(path: item.lastPathComponent))
            }
            return
        }

        var data = try Data(contentsOf: fileURL)
        if fileURL.pathExtension.lowercased() == "crx" {
            data = try Self.zipData(fromCRX: data)
        }
        let zip = destination.appending(path: "package.zip")
        try data.write(to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }

        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path(percentEncoded: false), destination.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0,
              FileManager.default.fileExists(atPath: destination.appending(path: "manifest.json").path(percentEncoded: false))
        else { throw InstallError.unsupportedFile }
    }

    /// Un .crx es un .zip con una cabecera firmada delante; aquí se quita la cabecera.
    nonisolated static func zipData(fromCRX data: Data) throws -> Data {
        func uint32(at offset: Int) -> Int {
            guard data.count >= offset + 4 else { return 0 }
            return data.subdata(in: offset..<offset + 4).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        }
        guard data.count > 16, data.prefix(4) == Data("Cr24".utf8) else { throw InstallError.unsupportedFile }
        let start: Int
        switch uint32(at: 4) {
        case 3: start = 12 + uint32(at: 8)
        case 2: start = 16 + uint32(at: 8) + uint32(at: 12)
        default: throw InstallError.unsupportedFile
        }
        guard start < data.count else { throw InstallError.unsupportedFile }
        return data.subdata(in: start..<data.count)
    }

    private func confirmInstall(_ webExtension: WKWebExtension, unsupported: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Añadir «\(webExtension.displayName ?? "extensión")»?"
        var lines: [String] = []
        if webExtension.allRequestedMatchPatterns.contains(where: { $0.matchesAllHosts }) {
            lines.append("• Leer y cambiar todos tus datos en todos los sitios web")
        } else if !webExtension.allRequestedMatchPatterns.isEmpty {
            let hosts = webExtension.allRequestedMatchPatterns.compactMap(\.host).prefix(4).joined(separator: ", ")
            lines.append("• Leer y cambiar tus datos en: \(hosts)")
        }
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        if !permissions.isEmpty {
            lines.append("• Permisos: \(permissions.joined(separator: ", "))")
        }
        alert.informativeText = lines.isEmpty ? "No pide permisos especiales." : "Podrá:\n" + lines.joined(separator: "\n")
        if !unsupported.isEmpty {
            alert.alertStyle = .warning
            alert.informativeText += "\n\n⚠️ Usa funciones de Chrome que Sunset (WebKit) no tiene, así que puede no funcionar o "
                + "funcionar a medias:\n" + unsupported.map { "• \($0)" }.joined(separator: "\n")
        }
        if let icon = webExtension.icon(for: CGSize(width: 64, height: 64)) { alert.icon = icon }
        alert.addButton(withTitle: "Añadir extensión")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Carga

    private func loadEnabledExtensions() async {
        for record in installed where record.isEnabled {
            await load(record)
        }
        onExtensionsLoaded?()
    }

    /// Al terminar de cargar las extensiones del arranque (las pestañas de extensiones que se
    /// restauraron antes no tenían aún su configuración y hay que volver a crearlas).
    @ObservationIgnored public var onExtensionsLoaded: (@MainActor () -> Void)?

    /// Carga la extensión. Los permisos que pidió se concedieron al instalarla.
    private func load(_ record: InstalledExtension, granting: Bool = true) async {
        guard contexts[record.id] == nil else { return }
        do {
            let webExtension = try await WKWebExtension(resourceBaseURL: folder(for: record.id))
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = record.id.uuidString
            // Dirección fija (si no, WebKit inventa una en cada arranque y las pestañas que la
            // extensión abrió dejan de cargar tras reiniciar Sunset).
            if let baseURL = URL(string: "webkit-extension://\(record.id.uuidString.lowercased())/") {
                context.baseURL = baseURL
            }
            context.isInspectable = true
            for permission in webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for pattern in webExtension.allRequestedMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
            try controller.load(context)
            contexts[record.id] = context

            // Presenta a la extensión las pestañas que ya estaban abiertas.
            for page in currentPages() { context.didOpenTab(page) }
            if let activePage { context.didActivateTab(activePage) }
            actionsRevision += 1
        } catch {
            lastError = "«\(record.name)»: \(message(for: error))"
        }
    }

    private func message(for error: Error) -> String {
        if case InstallError.cancelled = error { return "" }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Pestañas (las llama WebKitPage)

    func didOpen(_ page: WebKitPage) {
        openPages.removeAll { $0.page == nil }
        openPages.append(WeakPage(page: page))
        controller.didOpenTab(page)
    }

    func didClose(_ page: WebKitPage) {
        openPages.removeAll { $0.page == nil || $0.page === page }
        if activePage === page { activePage = nil }
        controller.didCloseTab(page)
    }

    func didActivate(_ page: WebKitPage) {
        let previous = activePage
        activePage = page
        controller.didActivateTab(page, previousActiveTab: previous)
        controller.didSelectTabs([page])
        actionsRevision += 1
    }

    func didChange(_ page: WebKitPage) {
        controller.didChangeTabProperties([.title, .URL, .loading], for: page)
    }

    /// Pestañas abiertas en el orden de la barra lateral.
    func currentPages() -> [WebKitPage] {
        if let ordered = orderedPages?().compactMap({ $0 as? WebKitPage }), !ordered.isEmpty { return ordered }
        return openPages.compactMap(\.page)
    }

    func currentActivePage() -> WebKitPage? { activePage }

    // MARK: - Registro

    private func folder(for id: UUID) -> URL {
        directory.appending(path: id.uuidString)
    }

    private var registryURL: URL { directory.appending(path: "Extensions.json") }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let records = try? JSONDecoder().decode([InstalledExtension].self, from: data) else { return }
        installed = records
    }

    private func saveRegistry() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(installed).write(to: registryURL, options: .atomic)
    }

    private struct WeakPage {
        weak var page: WebKitPage?
    }
}

// MARK: - Delegado del controlador

@available(macOS 15.4, *)
extension WebExtensionsHost: WKWebExtensionControllerDelegate {
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        [window]
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        window
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let page = openTab?(configuration.url) as? WebKitPage
        completionHandler(page, nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if let url = extensionContext.optionsPageURL { _ = openTab?(url) }
        completionHandler(nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let list = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        let allowed = confirm(extensionContext, asks: "Permisos adicionales: \(list)")
        completionHandler(allowed ? permissions : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let hosts = Set(urls.compactMap { $0.host() }).sorted().joined(separator: ", ")
        let allowed = confirm(extensionContext, asks: "Acceso a: \(hosts)")
        completionHandler(allowed ? urls : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let list = matchPatterns.map(\.string).sorted().joined(separator: ", ")
        let allowed = confirm(extensionContext, asks: "Acceso a: \(list)")
        completionHandler(allowed ? matchPatterns : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        actionsRevision += 1
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        // La ventana del navegador, aunque la app no esté en primer plano.
        let browserWindow = NSApp.mainWindow ?? NSApp.keyWindow
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
        guard let popover = action.popupPopover, let contentView = browserWindow?.contentView else {
            lastError = "«\(context.webExtension.displayName ?? "La extensión")» no pudo abrir su ventana."
            completionHandler(nil)
            return
        }
        // El rectángulo del botón llega en coordenadas de SwiftUI (origen arriba a la izquierda).
        let id = UUID(uuidString: context.uniqueIdentifier)
        var rect = id.flatMap { popupAnchor[$0] } ?? CGRect(x: contentView.bounds.maxX - 60, y: 0, width: 30, height: 30)
        if !contentView.isFlipped {
            rect.origin.y = contentView.bounds.height - rect.maxY
        }
        popover.behavior = .transient
        // El popover se cierra solo si la app no está activa: se trae al frente primero.
        NSApp.activate()
        browserWindow?.makeKeyAndOrderFront(nil)
        popover.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        completionHandler(nil)
    }

    private func confirm(_ context: WKWebExtensionContext, asks request: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "«\(context.webExtension.displayName ?? "Una extensión")» pide permiso"
        alert.informativeText = request
        alert.addButton(withTitle: "Permitir")
        alert.addButton(withTitle: "No permitir")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Ventana y pestañas vistas por las extensiones

/// La ventana del navegador tal como la ven las extensiones (`chrome.windows`).
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var host: WebExtensionsHost?

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        host?.currentPages() ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        host?.currentActivePage()
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.frame ?? .zero
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        NSApp.activate()
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

/// Cada página es una pestaña para las extensiones (`chrome.tabs`).
@available(macOS 15.4, *)
extension WebKitPage: WKWebExtensionTab {
    private var host: WebExtensionsHost? { extensionsHost as? WebExtensionsHost }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        host?.window
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        host?.currentPages().firstIndex { $0 === self } ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { webView.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { isActive }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }
    func size(for context: WKWebExtensionContext) -> CGSize { webView.bounds.size }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        onRequestActivate?()
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        onRequestClose?()
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goForward()
        completionHandler(nil)
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        webView.pageZoom = zoomFactor
        completionHandler(nil)
    }
}
