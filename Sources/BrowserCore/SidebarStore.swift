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
        public var color: SpaceColor
        public var pinned: [ItemRecord]
        public var tabs: [TabRecord]
        public var selectedTabID: UUID?
    }

    public var favorites: [TabRecord]
    public var spaces: [SpaceRecord]
    public var activeSpaceID: UUID?
    public var archive: [ArchivedTab]
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
