import SwiftUI
import BrowserCore

/// Caché de iconos de sitios, en memoria y en disco. Cada dominio se descarga una sola vez.
@MainActor
@Observable
public final class FaviconCache {
    public static let shared = FaviconCache()

    private var images: [String: NSImage] = [:]
    /// Último icono pedido por dominio, para no repetir descargas.
    @ObservationIgnored private var requested: [String: URL] = [:]
    @ObservationIgnored private let directory: URL
    /// Si la descarga normal falla (401 en sitios con contraseña HTTP o sesión), la app pide el
    /// icono a la página abierta de ese sitio, con su sesión.
    @ObservationIgnored public var sessionFetcher: (@MainActor (URL) async -> Data?)?

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "MiNavegador/Favicons")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func image(for host: String) -> NSImage? {
        images[host]
    }

    /// Clave de la caché: el dominio y, si lo hay, el puerto (cada proyecto en localhost tiene el suyo).
    public static func key(for url: URL?) -> String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return url?.port.map { "\(host):\($0)" } ?? host
    }

    /// Carga el icono del dominio desde disco o internet, si aún no se tiene.
    /// Si la página declara su propio icono, sustituye al `/favicon.ico` genérico.
    public func load(pageURL: URL?, iconURL: URL?) async {
        guard pageURL?.scheme == "http" || pageURL?.scheme == "https",
              let host = Self.key(for: pageURL),
              let candidate = iconURL ?? URL(string: "\(pageURL?.scheme ?? "https")://\(host)/favicon.ico")
        else { return }

        let previous = requested[host]
        guard previous != candidate, previous == nil || iconURL != nil else { return }
        requested[host] = candidate

        let file = directory.appending(path: host)
        // Junto al icono se guarda de dónde salió: si la página declara otro, se vuelve a descargar.
        let sourceFile = directory.appending(path: host + ".source")
        if previous == nil, let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            images[host] = image
            let source = (try? String(contentsOf: sourceFile, encoding: .utf8)).flatMap(URL.init(string:))
            if iconURL == nil || source == candidate { return }
        }

        var data: Data?
        if let (downloaded, response) = try? await URLSession.shared.data(from: candidate),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            data = downloaded
        } else if let sessionFetcher {
            data = await sessionFetcher(candidate)
        }
        guard let data, let image = NSImage(data: data), image.isValid else {
            // Puede que aún no se haya iniciado sesión: otro intento más tarde (cuando la página
            // declare su icono) vuelve a probar.
            requested[host] = previous
            return
        }
        images[host] = image
        try? data.write(to: file, options: .atomic)
        try? candidate.absoluteString.write(to: sourceFile, atomically: true, encoding: .utf8)
    }
}

/// Icono de un sitio.
public struct FaviconView: View {
    let pageURL: URL?
    let faviconURL: URL?
    var size: CGFloat

    public init(pageURL: URL?, faviconURL: URL? = nil, size: CGFloat = 16) {
        self.pageURL = pageURL
        self.faviconURL = faviconURL
        self.size = size
    }

    public init(tab: BrowserTab, size: CGFloat = 16) {
        self.init(pageURL: tab.url, faviconURL: tab.faviconURL, size: size)
    }

    public var body: some View {
        let cache = FaviconCache.shared
        Group {
            if HomePage.isHome(pageURL) {
                Image(systemName: "house.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            } else if let key = FaviconCache.key(for: pageURL), let image = cache.image(for: key) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .transition(.opacity)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: "\(FaviconCache.key(for: pageURL) ?? "")|\(faviconURL?.absoluteString ?? "")") {
            await cache.load(pageURL: pageURL, iconURL: faviconURL)
        }
    }
}
