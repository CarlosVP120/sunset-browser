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
}
