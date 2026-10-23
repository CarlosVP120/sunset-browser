import XCTest
import BrowserEngine
@testable import BrowserCore

@MainActor
final class DeveloperModeTests: XCTestCase {
    func testDetectsLocalDevelopmentSites() {
        for local in ["http://localhost:3005/x", "http://127.0.0.1:8080", "http://app.localhost", "https://shop.test",
                      "http://mac.local:3000", "http://192.168.1.20:5173", "http://10.0.0.4", "http://172.20.1.1", "http://[::1]:4000"] {
            XCTAssertTrue(DeveloperMode.isLocalDevelopment(URL(string: local)), local)
        }
        for remote in ["https://google.com", "https://localhost.com", "http://172.32.0.1", "http://8.8.8.8", "file:///tmp/a.html"] {
            XCTAssertFalse(DeveloperMode.isLocalDevelopment(URL(string: remote)), remote)
        }
        XCTAssertEqual(DeveloperMode.hostAndPort(URL(string: "http://localhost:3005/comprobante")), "localhost:3005")
    }

    func testTabsEnterDeveloperModeAndCanBeToggledPerSite() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let browser = Browser(engine: FakeEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              defaults: defaults, startsBackgroundWork: false)
        let local = browser.openTab(URL(string: "http://localhost:3005/"))
        XCTAssertTrue(local.isDeveloperMode)
        let site = browser.openTab(URL(string: "https://staging.example.com/"))
        XCTAssertFalse(site.isDeveloperMode)

        // Activarlo a mano en un sitio que no es local, y que se recuerde.
        browser.toggleDeveloperMode()
        XCTAssertTrue(site.isDeveloperMode)
        XCTAssertEqual(defaults.dictionary(forKey: "developerSites") as? [String: Bool], ["staging.example.com": true])

        // Desactivarlo vuelve a lo automático (no se guarda nada).
        browser.toggleDeveloperMode()
        XCTAssertFalse(site.isDeveloperMode)
        XCTAssertEqual(defaults.dictionary(forKey: "developerSites") as? [String: Bool], [:])

        // En localhost se puede apagar.
        browser.select(local)
        browser.toggleDeveloperMode()
        XCTAssertFalse(local.isDeveloperMode)
    }

    func testConsoleCountsUnseenErrorsAndKeepsTheLast500() {
        var log = ConsoleLog()
        log.append(ConsoleMessage(level: .error, text: "boom"), isVisible: false)
        log.append(ConsoleMessage(level: .log, text: "hola"), isVisible: false)
        log.append(ConsoleMessage(level: .error, text: "visto"), isVisible: true)
        XCTAssertEqual(log.unseenErrors, 1)
        log.markSeen()
        XCTAssertEqual(log.unseenErrors, 0)
        for index in 0..<600 { log.append(ConsoleMessage(level: .log, text: "\(index)"), isVisible: true) }
        XCTAssertEqual(log.messages.count, 500)
        XCTAssertEqual(log.messages.last?.text, "599")
    }

    func testNetworkLogStartsOverOnANewPageAndCountsFailures() {
        var log = NetworkLog()
        log.append(NetworkRequest(method: "GET", url: "http://localhost:3000/", status: 200, kind: .document, duration: 20, size: 1000,
                                  isNewDocument: true))
        log.append(NetworkRequest(method: "GET", url: "http://localhost:3000/app.js", status: 200, kind: .js, duration: 5, size: 500))
        log.append(NetworkRequest(method: "POST", url: "http://localhost:3000/api/login", status: 500, kind: .fetch, duration: 80, size: 0))
        XCTAssertEqual(log.requests.count, 3)
        XCTAssertEqual(log.totalSize, 1500)
        XCTAssertEqual(log.requests.filter(\.isFailure).map(\.name), ["login"])
        XCTAssertEqual(log.requests[0].name, "localhost/")

        log.append(NetworkRequest(method: "GET", url: "http://localhost:3000/otra", status: 200, kind: .document, duration: 10, size: 10,
                                  isNewDocument: true))
        XCTAssertEqual(log.requests.map(\.name), ["otra"])
    }
}
