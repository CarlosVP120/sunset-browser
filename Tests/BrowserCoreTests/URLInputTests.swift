import XCTest
@testable import BrowserCore

final class URLInputTests: XCTestCase {
    func testKeepsFullURLs() {
        XCTAssertEqual(URLInput.resolve("https://apple.com/mac")?.absoluteString, "https://apple.com/mac")
    }

    func testAddsHTTPSToHosts() {
        XCTAssertEqual(URLInput.resolve("github.com")?.absoluteString, "https://github.com")
        XCTAssertEqual(URLInput.resolve("  wikipedia.org/wiki/Arc  ")?.absoluteString, "https://wikipedia.org/wiki/Arc")
        XCTAssertEqual(URLInput.resolve("localhost:3000")?.absoluteString, "https://localhost:3000")
    }

    func testSearchesEverythingElse() {
        XCTAssertEqual(
            URLInput.resolve("mejor navegador")?.absoluteString,
            "https://www.google.com/search?q=mejor%20navegador"
        )
        XCTAssertEqual(URLInput.resolve("swift")?.host(), "www.google.com")
    }

    func testIgnoresEmptyInput() {
        XCTAssertNil(URLInput.resolve("   "))
    }
}
