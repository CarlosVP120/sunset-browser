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

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "MiNavegador/Favicons")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func image(for host: String) -> NSImage? {
        images[host]
    }

    /// Carga el icono del dominio desde disco o internet, si aún no se tiene.
    /// Si la página declara su propio icono, sustituye al `/favicon.ico` genérico.
    public func load(pageURL: URL?, iconURL: URL?) async {
        guard let host = pageURL?.host(), !host.isEmpty,
              let candidate = iconURL ?? URL(string: "https://\(host)/favicon.ico")
        else { return }

        let previous = requested[host]
        guard previous != candidate, previous == nil || iconURL != nil else { return }
        requested[host] = candidate

        let file = directory.appending(path: host)
        if previous == nil, let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            images[host] = image
            return
        }

        guard let (data, response) = try? await URLSession.shared.data(from: candidate),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), image.isValid
        else { return }
        images[host] = image
        try? data.write(to: file, options: .atomic)
    }
}

/// Icono del sitio de una pestaña.
public struct FaviconView: View {
    let tab: BrowserTab
    var size: CGFloat

    public init(tab: BrowserTab, size: CGFloat = 16) {
        self.tab = tab
        self.size = size
    }

    public var body: some View {
        let cache = FaviconCache.shared
        Group {
            if let host = tab.url?.host(), let image = cache.image(for: host) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: "\(tab.url?.host() ?? "")|\(tab.faviconURL?.absoluteString ?? "")") {
            await cache.load(pageURL: tab.url, iconURL: tab.faviconURL)
        }
    }
}
