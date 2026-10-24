import WebKit
import Observation

/// Una descarga (en curso o terminada). Se guardan en `Downloads.json` para la Librería.
public struct DownloadRecord: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case inProgress, finished, failed, cancelled
    }

    public let id: UUID
    public var filename: String
    public var fileURL: URL?
    /// Página o enlace de donde viene.
    public var sourceURL: URL?
    public var date: Date
    public var totalBytes: Int64?
    public var state: State

    public var sourceHost: String? {
        guard let host = sourceURL?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Si el archivo sigue en su sitio (no se ha borrado ni movido).
    public var fileExists: Bool {
        guard let path = fileURL?.path(percentEncoded: false) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Gestiona las descargas de todas las pestañas: dónde guardarlas, progreso, historial y acciones.
@MainActor
@Observable
public final class DownloadManager: NSObject {
    /// Las más recientes primero.
    public private(set) var items: [DownloadRecord] = []
    /// Progreso (0–1) de las que están en curso.
    public private(set) var progress: [UUID: Double] = [:]
    /// Avisa cuando una descarga termina (para el aviso en pantalla).
    @ObservationIgnored public var onFinish: ((DownloadRecord) -> Void)?

    @ObservationIgnored private var active: [ObjectIdentifier: ActiveDownload] = [:]
    @ObservationIgnored private let registryURL: URL?
    @ObservationIgnored private let downloadsFolder: URL

    private struct ActiveDownload {
        let id: UUID
        let download: WKDownload
        let observation: NSKeyValueObservation
    }

    public init(registryURL: URL? = DownloadManager.standardRegistryURL,
                downloadsFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.registryURL = registryURL
        self.downloadsFolder = downloadsFolder
        super.init()
        if let registryURL, let data = try? Data(contentsOf: registryURL),
           var saved = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            // Las que estaban en curso al cerrar la app ya no lo están.
            for index in saved.indices where saved[index].state == .inProgress { saved[index].state = .failed }
            items = saved
        }
    }

    nonisolated public static var standardRegistryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "MiNavegador/Downloads.json")
    }

    public var activeCount: Int { progress.count }

    /// Progreso total de las descargas en curso (para el anillo del botón de la Librería).
    public var overallProgress: Double? {
        guard !progress.isEmpty else { return nil }
        return progress.values.reduce(0, +) / Double(progress.count)
    }

    /// Empieza a seguir una descarga que ha creado una página.
    func track(_ download: WKDownload) {
        download.delegate = self
    }

    // MARK: - Acciones

    public func open(_ record: DownloadRecord) {
        guard let url = record.fileURL, record.fileExists else { return }
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(_ record: DownloadRecord) {
        guard let url = record.fileURL else { return }
        if record.fileExists {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(downloadsFolder)
        }
    }

    public func cancel(_ record: DownloadRecord) {
        guard let entry = active.first(where: { $0.value.id == record.id }) else { return }
        entry.value.download.cancel { _ in }
        finish(entry.key, state: .cancelled)
    }

    /// Quita la descarga de la lista (el archivo se queda donde está).
    public func removeFromList(_ record: DownloadRecord) {
        if record.state == .inProgress { cancel(record) }
        items.removeAll { $0.id == record.id }
        save()
    }

    public func moveToTrash(_ record: DownloadRecord) {
        if let url = record.fileURL, record.fileExists {
            NSWorkspace.shared.recycle([url])
        }
        removeFromList(record)
    }

    public func clearList() {
        items.removeAll { $0.state != .inProgress }
        save()
    }

    // MARK: - Interno

    private func uniqueDestination(for filename: String) -> URL {
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        var candidate = downloadsFolder.appending(path: safeName)
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = downloadsFolder.appending(path: name)
            number += 1
        }
        return candidate
    }

    private func finish(_ key: ObjectIdentifier, state: DownloadRecord.State) {
        guard let entry = active.removeValue(forKey: key) else { return }
        progress[entry.id] = nil
        guard let index = items.firstIndex(where: { $0.id == entry.id }) else { return }
        items[index].state = state
        if state == .finished, let url = items[index].fileURL {
            markAsDownloaded(url, from: items[index].sourceURL)
            // Hace rebotar la pila de Descargas del Dock, como Safari.
            DistributedNotificationCenter.default().post(
                name: Notification.Name("com.apple.DownloadFileFinished"),
                object: url.path(percentEncoded: false)
            )
            onFinish?(items[index])
        }
        save()
    }

    /// Marca el archivo como descargado de internet: macOS avisará antes de abrir apps o scripts.
    private func markAsDownloaded(_ url: URL, from source: URL?) {
        var values = URLResourceValues()
        var quarantine: [String: Any] = [
            kLSQuarantineAgentNameKey as String: "Sunset",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        if let source { quarantine[kLSQuarantineDataURLKey as String] = source }
        values.quarantineProperties = quarantine
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private func save() {
        guard let registryURL else { return }
        try? FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(items.prefix(500))).write(to: registryURL, options: .atomic)
    }
}

extension DownloadManager: WKDownloadDelegate {
    public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let destination = uniqueDestination(for: suggestedFilename)
        let id = UUID()
        let record = DownloadRecord(
            id: id,
            filename: destination.lastPathComponent,
            fileURL: destination,
            sourceURL: download.originalRequest?.url ?? response.url,
            date: Date(),
            totalBytes: response.expectedContentLength > 0 ? response.expectedContentLength : nil,
            state: .inProgress
        )
        items.insert(record, at: 0)
        progress[id] = 0

        let key = ObjectIdentifier(download)
        let observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, self.progress[id] != nil else { return }
                self.progress[id] = fraction
            }
        }
        active[key] = ActiveDownload(id: id, download: download, observation: observation)
        save()
        return destination
    }

    public func downloadDidFinish(_ download: WKDownload) {
        finish(ObjectIdentifier(download), state: .finished)
    }

    public func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(ObjectIdentifier(download), state: .failed)
    }
}
