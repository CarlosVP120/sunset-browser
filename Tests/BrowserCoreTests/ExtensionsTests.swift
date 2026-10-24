import XCTest
@testable import BrowserEngine

@available(macOS 15.4, *)
final class ExtensionsTests: XCTestCase {
    func testStripsCRX3Header() throws {
        let zip = Data("PK\u{3}\u{4}contenido".utf8)
        var crx = Data("Cr24".utf8)
        crx.append(contentsOf: [3, 0, 0, 0])          // versión 3
        crx.append(contentsOf: [5, 0, 0, 0])          // cabecera de 5 bytes
        crx.append(contentsOf: [1, 2, 3, 4, 5])
        crx.append(zip)

        XCTAssertEqual(try WebExtensionsHost.zipData(fromCRX: crx), zip)
    }

    func testRejectsFilesThatAreNotCRX() {
        XCTAssertThrowsError(try WebExtensionsHost.zipData(fromCRX: Data("PK\u{3}\u{4}0123456789abcdef".utf8)))
    }

    func testRecognizesChromeWebStorePages() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        XCTAssertEqual(
            WebExtensionsHost.chromeWebStoreID(from: URL(string: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)")),
            id
        )
        XCTAssertEqual(
            WebExtensionsHost.chromeWebStoreID(from: URL(string: "https://chrome.google.com/webstore/detail/x/\(id)?hl=es")),
            id
        )
        XCTAssertNil(WebExtensionsHost.chromeWebStoreID(from: URL(string: "https://github.com/\(id)")))
    }

    /// Claude para Chrome pide APIs que WebKit no tiene; SVG Gobbler, ninguna.
    func testFlagsChromeOnlyAPIs() {
        let claude: [String: Any] = [
            "permissions": ["sidePanel", "storage", "activeTab", "scripting", "debugger", "tabGroups", "tabs", "alarms",
                            "notifications", "webNavigation", "declarativeNetRequestWithHostAccess", "offscreen",
                            "nativeMessaging", "unlimitedStorage", "downloads", "identity"],
        ]
        let flagged = ExtensionCompatibility.unsupportedFeatures(manifest: claude)
        XCTAssertEqual(flagged.count, 6)
        XCTAssertTrue(flagged.contains { $0.contains("chrome.debugger") })
        XCTAssertTrue(flagged.contains { $0.contains("chrome.sidePanel") })

        let svgGobbler: [String: Any] = ["permissions": ["activeTab", "scripting", "storage", "contextMenus"]]
        XCTAssertEqual(ExtensionCompatibility.unsupportedFeatures(manifest: svgGobbler), [])

        // El panel lateral declarado solo con su clave del manifiesto también cuenta.
        let panelOnly: [String: Any] = ["side_panel": ["default_path": "panel.html"]]
        XCTAssertEqual(ExtensionCompatibility.unsupportedFeatures(manifest: panelOnly).count, 1)
    }
}
