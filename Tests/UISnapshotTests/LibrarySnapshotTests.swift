import SwiftUI
import XCTest
@testable import BrowserCore
@testable import BrowserEngine
@testable import BrowserUI
@testable import LibraryFeature

@MainActor
final class LibrarySnapshotTests: XCTestCase {
    private final class NoEngine: WebEngine {
        func makePage(profile: UUID?) -> WebPage { fatalError("No se usan páginas en las capturas") }
        func removeProfileData(_ profile: UUID) {}
        func clearBrowsingData(_ kinds: BrowsingData, host: String?) async {}
        func importCookies(_ cookies: [HTTPCookie], profile: UUID?) async {}
    }

    func testLibraryDownloads() throws {
        let records = [
            ("factura_2026-09.pdf", "https://example.com/x", 2.0),
            ("reunión-20260924.mov", "https://skype.com/x", 28),
            ("54c17fead6de8697bb23bea62.jpg", "https://cdn.sanity.io/x", 33),
            ("smtp-credentials.csv", nil, 60),
        ].map { name, source, days in
            DownloadRecord(id: UUID(), filename: name, fileURL: nil, sourceURL: source.flatMap(URL.init(string:)),
                           date: Date().addingTimeInterval(-days * 86_400), totalBytes: nil, state: .finished)
        }
        let registry = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try JSONEncoder().encode(records).write(to: registry)
        defer { try? FileManager.default.removeItem(at: registry) }

        let browser = Browser(engine: NoEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        browser.librarySection = .downloads
        let view = LibraryView(browser: browser, downloads: DownloadManager(registryURL: registry))
            .frame(width: 420, height: 640)
            .background(Color(SpaceTheme.default.background[0]))
            .environment(\.spaceTheme, .default)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        let folder = FileManager.default.temporaryDirectory.appending(path: "MiNavegador-snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appending(path: "library.png"))
        print("Captura: \(folder.appending(path: "library.png").path)")
    }
}
