import Foundation

/// Convierte lo que el usuario escribe en una URL: una dirección o una búsqueda.
public enum URLInput {
    public static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }

        if looksLikeHost(text) {
            // Los servidores locales de desarrollo casi nunca tienen HTTPS.
            let scheme = text.hasPrefix("localhost") || text.hasPrefix("127.0.0.1") ? "http" : "https"
            if let url = URL(string: "\(scheme)://\(text)") { return url }
        }

        return searchURL(for: text)
    }

    public static func searchURL(for query: String) -> URL? {
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: query)]
        return search.url
    }

    public static func isSearch(_ url: URL) -> Bool {
        url.host() == "www.google.com" && url.path() == "/search"
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        if host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") { return true }
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }
}
