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

        if looksLikeHost(text), let url = URL(string: "https://\(text)") {
            return url
        }

        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        if host.hasPrefix("localhost") { return true }
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }
}
