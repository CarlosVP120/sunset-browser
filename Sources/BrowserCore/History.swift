import Foundation
import Observation

public struct HistoryEntry: Codable, Equatable, Sendable {
    public var url: URL
    public var title: String
    public var visitCount: Int
    public var lastVisit: Date
}

/// Historial de navegación: alimenta las sugerencias del Command Bar.
@MainActor
@Observable
public final class History {
    public private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let limit = 3000

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            self.entries = entries
        }
    }

    nonisolated public static var standardFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "MiNavegador/History.json")
    }

    /// Registra una visita. Si la URL ya estaba, actualiza título, contador y fecha.
    public func record(url: URL, title: String, now: Date = Date()) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        if let index = entries.firstIndex(where: { $0.url == url }) {
            let isNewVisit = now.timeIntervalSince(entries[index].lastVisit) > 30
            if !title.isEmpty { entries[index].title = title }
            if isNewVisit { entries[index].visitCount += 1 }
            entries[index].lastVisit = now
        } else {
            entries.append(HistoryEntry(url: url, title: title, visitCount: 1, lastVisit: now))
            if entries.count > Self.limit {
                entries.sort { $0.lastVisit > $1.lastVisit }
                entries.removeLast(entries.count - Self.limit)
            }
        }
        scheduleSave()
    }

    /// Entradas que coinciden con la búsqueda, de más a menos relevante.
    public func search(_ query: String, limit: Int, now: Date = Date()) -> [HistoryEntry] {
        let needle = query.searchNormalized
        guard !needle.isEmpty else {
            return Array(entries.sorted { $0.lastVisit > $1.lastVisit }.prefix(limit))
        }
        return entries
            .compactMap { entry -> (HistoryEntry, Double)? in
                let host = (entry.url.host() ?? "").searchNormalized
                let host1 = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let title = entry.title.searchNormalized
                let url = entry.url.absoluteString.searchNormalized
                var score: Double
                if host1.hasPrefix(needle) { score = 4 }
                else if title.hasPrefix(needle) { score = 3 }
                else if title.contains(needle) || host.contains(needle) { score = 2 }
                else if url.contains(needle) { score = 1 }
                else { return nil }
                let days = now.timeIntervalSince(entry.lastVisit) / 86_400
                score += log2(Double(entry.visitCount) + 1) - min(days / 30, 2)
                return (entry, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func scheduleSave() {
        guard let fileURL else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            guard let data = try? JSONEncoder().encode(self.entries) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension String {
    /// Minúsculas y sin acentos, para comparar búsquedas.
    public var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
