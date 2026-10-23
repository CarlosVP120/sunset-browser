import Foundation

/// Importa la barra lateral de Arc (favoritos, espacios, carpetas y pestañas)
/// desde `~/Library/Application Support/Arc/StorableSidebar.json`.
public enum ArcImporter {
    public enum ImportError: Error {
        case unreadableFile
        case unexpectedFormat
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Arc/StorableSidebar.json")
    }

    public static func load(from fileURL: URL = defaultFileURL) throws -> SidebarSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ImportError.unreadableFile }

        // Arc guarda dos contenedores; el segundo es el de la barra lateral actual.
        guard let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["items"] != nil })
        else { throw ImportError.unexpectedFormat }

        // Las listas de Arc alternan [id, objeto, id, objeto…].
        let items = (container["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let itemsByID = Dictionary(items.compactMap { item in (item["id"] as? String).map { ($0, item) } },
                                   uniquingKeysWith: { first, _ in first })

        func children(of containerID: String?) -> [[String: Any]] {
            guard let containerID, let ids = itemsByID[containerID]?["childrenIds"] as? [String] else { return [] }
            return ids.compactMap { itemsByID[$0] }
        }

        func tabRecord(_ item: [String: Any]) -> SidebarSnapshot.TabRecord? {
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
            let url = (tab["savedURL"] as? String).flatMap(URL.init(string:))
            let customTitle = item["title"] as? String
            let title = customTitle ?? tab["savedTitle"] as? String ?? ""
            return .init(id: uuid(item["id"]), url: url, title: title, faviconURL: nil)
        }

        /// Pestañas de una carpeta, aplanando las subcarpetas.
        func folderTabs(_ item: [String: Any]) -> [SidebarSnapshot.TabRecord] {
            children(of: item["id"] as? String).flatMap { child -> [SidebarSnapshot.TabRecord] in
                if let tab = tabRecord(child) { return [tab] }
                return folderTabs(child)
            }
        }

        func itemRecord(_ item: [String: Any]) -> SidebarSnapshot.ItemRecord? {
            if let tab = tabRecord(item) { return .tab(tab) }
            guard (item["data"] as? [String: Any])?["list"] != nil else { return nil }
            return .folder(.init(
                id: uuid(item["id"]),
                name: item["title"] as? String ?? "Carpeta",
                isExpanded: false,
                tabs: folderTabs(item)
            ))
        }

        let topApps = container["topAppsContainerIDs"] as? [Any] ?? []
        let favoritesID = topApps.compactMap { $0 as? String }.first
        let favorites = children(of: favoritesID).compactMap(tabRecord)

        let spaceObjects = (container["spaces"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let spaces = spaceObjects.enumerated().map { index, space -> SidebarSnapshot.SpaceRecord in
            let containerIDs = space["containerIDs"] as? [Any] ?? []
            func containerID(_ name: String) -> String? {
                guard let index = containerIDs.firstIndex(where: { ($0 as? String) == name }),
                      index + 1 < containerIDs.count else { return nil }
                return containerIDs[index + 1] as? String
            }
            let customInfo = space["customInfo"] as? [String: Any]
            return .init(
                id: uuid(space["id"]),
                name: space["title"] as? String ?? "Espacio",
                icon: icon(from: customInfo),
                theme: theme(from: customInfo, fallback: SpaceColor.palette[index % SpaceColor.palette.count]),
                pinned: children(of: containerID("pinned")).compactMap(itemRecord),
                tabs: children(of: containerID("unpinned")).compactMap(tabRecord),
                selectedTabID: nil
            )
        }

        guard !spaces.isEmpty else { throw ImportError.unexpectedFormat }
        return SidebarSnapshot(favorites: favorites, spaces: spaces, activeSpaceID: spaces.first?.id, archive: [])
    }

    private static func uuid(_ value: Any?) -> UUID {
        (value as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    private static let iconMap = [
        "code": "chevron.left.forwardslash.chevron.right",
        "planet": "globe.americas",
        "star": "star",
        "heart": "heart",
        "bolt": "bolt",
        "book": "book",
        "briefcase": "briefcase",
        "house": "house",
        "music": "music.note",
    ]

    private static func icon(from customInfo: [String: Any]?) -> String {
        let iconType = customInfo?["iconType"] as? [String: Any]
        if let emoji = iconType?["emoji_v2"] as? String ?? iconType?["emoji"] as? String { return emoji }
        if let name = iconType?["icon"] as? String { return iconMap[name] ?? "circle.grid.2x2" }
        return "circle.grid.2x2"
    }

    /// Convierte el `windowTheme` de Arc: colores de fondo, grano y paleta de hover/selección.
    static func theme(from customInfo: [String: Any]?, fallback: SpaceColor) -> SpaceTheme {
        let windowTheme = customInfo?["windowTheme"] as? [String: Any] ?? [:]
        let background = windowTheme["background"] ?? [:]

        let backgroundColors = colors(in: background)
        let primaryPalette = windowTheme["primaryColorPalette"] as? [String: Any]
        let base = backgroundColors.first ?? primaryPalette.flatMap { color($0["shaded"]) } ?? fallback

        let isDark = firstValue(forKey: "contentOverBackgroundAppearance", in: background) as? String != "light"
        var theme = SpaceTheme.dark(from: base, grain: firstValue(forKey: "noiseFactor", in: background) as? Double ?? 0)
        theme.background = backgroundColors.isEmpty ? [base] : backgroundColors
        theme.isDark = isDark

        let palettes = (windowTheme["semanticColorPalette"] as? [String: Any])?["appearanceBased"] as? [String: Any]
        if let palette = palettes?[isDark ? "dark" : "light"] as? [String: Any] {
            theme.hover = color(palette["hover"]) ?? theme.hover
            theme.focus = color(palette["focus"]) ?? theme.focus
            theme.title = color(palette["title"]) ?? theme.title
            theme.subtitle = color(palette["subtitle"]) ?? theme.subtitle
            theme.accent = color(palette["foregroundSecondary"]) ?? theme.accent
        }
        return theme
    }

    private static func color(_ value: Any?) -> SpaceColor? {
        guard let dict = value as? [String: Any],
              let red = dict["red"] as? Double, let green = dict["green"] as? Double, let blue = dict["blue"] as? Double
        else { return nil }
        return SpaceColor(red: red, green: green, blue: blue, alpha: dict["alpha"] as? Double ?? 1)
    }

    /// Todos los colores dentro de un valor, en orden (los degradados guardan sus colores en listas).
    private static func colors(in value: Any) -> [SpaceColor] {
        if let color = color(value) { return [color] }
        if let array = value as? [Any] { return array.flatMap(colors(in:)) }
        if let dict = value as? [String: Any] {
            return dict.keys.sorted().flatMap { colors(in: dict[$0]!) }
        }
        return []
    }

    private static func firstValue(forKey key: String, in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let found = dict[key] { return found }
            for nested in dict.values {
                if let found = firstValue(forKey: key, in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = firstValue(forKey: key, in: nested) { return found }
            }
        }
        return nil
    }
}
