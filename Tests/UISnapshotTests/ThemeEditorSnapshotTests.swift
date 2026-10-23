import SwiftUI
import XCTest
import BrowserEngine
@testable import BrowserCore
@testable import SidebarFeature

/// Guarda capturas de vistas en la carpeta temporal (`MiNavegador-snapshots`) para revisarlas.
@MainActor
final class ThemeEditorSnapshotTests: XCTestCase {
    private final class NoEngine: WebEngine {
        func makePage(profile: UUID?) -> WebPage { fatalError("No se usan páginas en las capturas") }
        func removeProfileData(_ profile: UUID) {}
        func clearBrowsingData(_ kinds: BrowsingData, host: String?) async {}
        func importCookies(_ cookies: [HTTPCookie], profile: UUID?) async {}
    }

    private func render<V: View>(_ view: V, named name: String) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let folder = FileManager.default.temporaryDirectory.appending(path: "MiNavegador-snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).png")
        try png.write(to: url)
        print("Captura: \(url.path)")
        return url
    }

    func testThemeEditor() throws {
        let browser = Browser(engine: NoEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        let space = browser.activeSpace
        browser.setTheme(.make(seeds: [SpaceColor(hue: 0.62, saturation: 0.75, brightness: 1),
                                       SpaceColor(hue: 0.8, saturation: 0.55, brightness: 1)],
                               appearance: .dark, intensity: 0.45, grain: 0.4), for: space)

        let view = ThemeEditor(browser: browser, space: space)
            .background(Color(white: 0.17))
        _ = try render(view, named: "theme-editor")
    }
}
