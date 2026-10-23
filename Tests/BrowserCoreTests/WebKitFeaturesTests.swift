import WebKit
import XCTest
@testable import BrowserEngine

@MainActor
final class WebKitFeaturesTests: XCTestCase {
    /// Si una actualización de macOS renombra estos ajustes, este test avisa.
    func testSmoothScrollingFeaturesExistInThisWebKit() {
        let preferences = WKPreferences()
        XCTAssertTrue(WebKitFeatures.set(WebKitFeatures.preferNear60FPS, enabled: false, on: preferences))
        XCTAssertTrue(WebKitFeatures.set(WebKitFeatures.scrollAnimator, enabled: true, on: preferences))
        XCTAssertFalse(WebKitFeatures.set("NoExiste", enabled: true, on: preferences))
    }
}
