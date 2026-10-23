import Foundation

/// Lo que se guarda en disco de la barra lateral (equivalente a `StorableSidebar.json` de Arc).
public struct SidebarSnapshot: Codable, Equatable, Sendable {
    public struct TabRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var url: URL?
        public var title: String
        public var faviconURL: URL?
    }

    public struct FolderRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var isExpanded: Bool
        public var tabs: [TabRecord]
    }

    public enum ItemRecord: Codable, Equatable, Sendable {
        case tab(TabRecord)
        case folder(FolderRecord)
    }

    public struct SpaceRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var icon: String
        public var theme: SpaceTheme
        public var profileID: UUID?
        public var pinned: [ItemRecord]
        public var tabs: [TabRecord]
        public var selectedTabID: UUID?

        public init(
            id: UUID,
            name: String,
            icon: String,
            theme: SpaceTheme,
            profileID: UUID? = nil,
            pinned: [ItemRecord],
            tabs: [TabRecord],
            selectedTabID: UUID?
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.theme = theme
            self.profileID = profileID
            self.pinned = pinned
            self.tabs = tabs
            self.selectedTabID = selectedTabID
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, icon, theme, color, profileID, pinned, tabs, selectedTabID
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            icon = try container.decode(String.self, forKey: .icon)
            // Las versiones anteriores solo guardaban un color.
            if let theme = try container.decodeIfPresent(SpaceTheme.self, forKey: .theme) {
                self.theme = theme
            } else {
                let color = try container.decodeIfPresent(SpaceColor.self, forKey: .color) ?? .navy
                theme = .dark(from: color)
            }
            profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
            pinned = try container.decode([ItemRecord].self, forKey: .pinned)
            tabs = try container.decode([TabRecord].self, forKey: .tabs)
            selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(icon, forKey: .icon)
            try container.encode(theme, forKey: .theme)
            try container.encodeIfPresent(profileID, forKey: .profileID)
            try container.encode(pinned, forKey: .pinned)
            try container.encode(tabs, forKey: .tabs)
            try container.encodeIfPresent(selectedTabID, forKey: .selectedTabID)
        }
    }

    public var favorites: [TabRecord]
    public var spaces: [SpaceRecord]
    public var activeSpaceID: UUID?
    public var archive: [ArchivedTab]
    public var profiles: [Profile]

    public init(
        favorites: [TabRecord],
        spaces: [SpaceRecord],
        activeSpaceID: UUID?,
        archive: [ArchivedTab],
        profiles: [Profile] = []
    ) {
        self.favorites = favorites
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.archive = archive
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey {
        case favorites, spaces, activeSpaceID, archive, profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([TabRecord].self, forKey: .favorites)
        spaces = try container.decode([SpaceRecord].self, forKey: .spaces)
        activeSpaceID = try container.decodeIfPresent(UUID.self, forKey: .activeSpaceID)
        archive = try container.decodeIfPresent([ArchivedTab].self, forKey: .archive) ?? []
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
    }
}

/// Lee y guarda la barra lateral en un archivo JSON.
public struct SidebarStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var standard: SidebarStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SidebarStore(fileURL: support.appending(path: "MiNavegador/Sidebar.json"))
    }

    public func load() -> SidebarSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SidebarSnapshot.self, from: data)
    }

    public func save(_ snapshot: SidebarSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
