import XCTest
@testable import BrowserCore

@MainActor
final class HomeTests: XCTestCase {
    private func makeBrowser() -> (Browser, FakeEngine) {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        return (browser, engine)
    }

    func testNewTabButtonOpensHomeWithoutLoadingAWebPage() throws {
        let (browser, engine) = makeBrowser()

        browser.openHome()

        let tab = try XCTUnwrap(browser.selectedTab)
        XCTAssertTrue(tab.isHome)
        XCTAssertEqual(tab.displayTitle, "Inicio")
        XCTAssertTrue(engine.pages.last?.loadedURLs.isEmpty ?? false, "Inicio no carga ninguna web")

        // Un segundo clic no crea otra pestaña Inicio: vuelve a la que había.
        browser.openTab(URL(string: "https://a.com"))
        browser.openHome()
        XCTAssertEqual(browser.activeSpace.tabs.filter(\.isHome).count, 1)
        XCTAssertEqual(browser.selectedTab?.id, tab.id)
    }

    func testSearchingFromHomeNavigatesInTheSameTab() throws {
        let (browser, engine) = makeBrowser()
        browser.openHome()
        let home = try XCTUnwrap(browser.selectedTab)

        browser.perform(Suggestion(id: "x", title: "a", action: .open(URL(string: "https://a.com")!)), mode: .currentTab)

        XCTAssertEqual(browser.selectedTab?.id, home.id)
        XCTAssertEqual(engine.pages.last?.loadedURLs.last?.host(), "a.com")
        XCTAssertEqual(browser.activeSpace.tabs.count, 1)
    }

    func testClosingHomeDoesNotFillTheArchive() {
        let (browser, _) = makeBrowser()
        browser.openHome()
        browser.closeSelectedTab()
        XCTAssertTrue(browser.archive.isEmpty)
    }

    func testPresentationModeAndPageCommands() {
        let (browser, _) = makeBrowser()
        browser.openHome()

        browser.perform(.togglePresenting)
        XCTAssertTrue(browser.isPresenting)
        browser.perform(.togglePresenting)
        XCTAssertFalse(browser.isPresenting)

        // En Inicio no tiene sentido copiar la URL ni recargar.
        let suggestions = browser.suggestions(for: "copiar", mode: .currentTab, searchSuggestions: [])
        XCTAssertFalse(suggestions.contains { $0.action == .command(.copyURL) })
    }
}
