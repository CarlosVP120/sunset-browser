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
                color: color(from: customInfo) ?? SpaceColor.palette[index % SpaceColor.palette.count],
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

    /// El primer color con componentes RGB que aparezca en el tema del espacio.
    private static func color(from customInfo: [String: Any]?) -> SpaceColor? {
        func search(_ value: Any) -> SpaceColor? {
            if let dict = value as? [String: Any] {
                if let red = dict["red"] as? Double, let green = dict["green"] as? Double, let blue = dict["blue"] as? Double {
                    return SpaceColor(red: red, green: green, blue: blue)
                }
                for key in dict.keys.sorted() {
                    if key == "semanticColorPalette" { continue }
                    if let found = search(dict[key]!) { return found }
                }
            } else if let array = value as? [Any] {
                for element in array {
                    if let found = search(element) { return found }
                }
            }
            return nil
        }
        return (customInfo?["windowTheme"]).flatMap(search)
    }
}
