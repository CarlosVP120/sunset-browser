import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers
import BrowserEngine

/// Miniatura real del archivo (Quick Look) o, si no hay, el icono de su tipo.
struct FileThumbnail: View {
    let record: DownloadRecord
    var size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                    .transition(.opacity)
            } else {
                Image(nsImage: Self.icon(for: record))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(record.id)-\(record.state.rawValue)") { await load() }
    }

    private func load() async {
        guard record.state == .finished, record.fileExists, let url = record.fileURL else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            withAnimation(.easeOut(duration: 0.2)) { image = thumbnail.nsImage }
        }
    }

    static func icon(for record: DownloadRecord) -> NSImage {
        if let url = record.fileURL, record.fileExists {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        let type = UTType(filenameExtension: (record.filename as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

/// Tipo de archivo, para el filtro y el subtítulo ("PDF de eqidis.com").
enum FileKind: String, CaseIterable, Identifiable {
    case all, images, videos, pdfs, documents, archives, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todo"
        case .images: "Imágenes"
        case .videos: "Vídeos"
        case .pdfs: "PDF"
        case .documents: "Documentos"
        case .archives: "Comprimidos"
        case .other: "Otros"
        }
    }

    /// Nombre en singular para el subtítulo de cada descarga.
    var singular: String {
        switch self {
        case .images: "Imagen"
        case .videos: "Vídeo"
        case .pdfs: "PDF"
        case .documents: "Documento"
        case .archives: "Archivo comprimido"
        case .all, .other: "Archivo"
        }
    }

    static func of(_ filename: String) -> FileKind {
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension) else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audiovisualContent) { return .videos }
        if type.conforms(to: .pdf) { return .pdfs }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .text) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation)
            || type.conforms(to: .compositeContent) {
            return .documents
        }
        return .other
    }
}

extension DownloadRecord {
    /// "PDF de eqidis.com", "Imagen de sanity.io"… o el estado si no ha terminado.
    var subtitle: String {
        switch state {
        case .failed: return "Error en la descarga"
        case .cancelled: return "Cancelada"
        case .inProgress, .finished:
            let kind = FileKind.of(filename).singular
            if let host = sourceHost { return "\(kind) de \(host)" }
            return kind
        }
    }

    /// "hace 2 días", "hoy"… para agrupar.
    var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoy" }
        if calendar.isDateInYesterday(date) { return "Ayer" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return formatter.localizedString(from: DateComponents(day: -days)) }
        if days < 30 { return formatter.localizedString(from: DateComponents(weekOfMonth: -(days / 7))) }
        if days < 365 { return formatter.localizedString(from: DateComponents(month: -(days / 30))) }
        return formatter.localizedString(from: DateComponents(year: -(days / 365)))
    }
}
