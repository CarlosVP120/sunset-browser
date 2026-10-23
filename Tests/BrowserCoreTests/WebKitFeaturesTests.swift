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

@MainActor
final class UserAgentTests: XCTestCase {
    /// Sin la parte de Safari, Google y otras webs sirven versiones antiguas.
    func testWePresentOurselvesAsSafari() {
        let suffix = WebKitEngine.safariUserAgentSuffix
        XCTAssertTrue(suffix.hasPrefix("Version/"))
        XCTAssertTrue(suffix.hasSuffix("Safari/605.1.15"))
    }
}
