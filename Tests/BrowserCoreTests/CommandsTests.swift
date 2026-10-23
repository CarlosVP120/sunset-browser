import XCTest
import BrowserEngine
@testable import BrowserCore

@MainActor
final class CommandsTests: XCTestCase {
    private func makeBrowser() -> (Browser, FakeEngine) {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        return (browser, engine)
    }

    func testTypingClearShowsTheClearCommandsFirst() {
        let (browser, _) = makeBrowser()
        browser.openTab(URL(string: "https://a.com"))
        browser.openTab(URL(string: "https://b.com"))

        let suggestions = browser.suggestions(for: "clear", mode: .newTab, searchSuggestions: [])
        let commands = suggestions.compactMap { suggestion -> BrowserCommand? in
            if case .command(let command) = suggestion.action { command } else { nil }
        }

        XCTAssertTrue(commands.contains(.clearCache))
        XCTAssertTrue(commands.contains(.clearSiteCookiesAndRefresh))
        XCTAssertTrue(commands.contains(.clearTodayTabs))
        // Van justo después del resultado directo (la búsqueda).
        XCTAssertEqual(suggestions.first?.detail, "Buscar en Google")
        if case .command = suggestions[1].action {} else { XCTFail("Los comandos deberían ir segundos") }

        // También en español.
        let spanish = browser.suggestions(for: "limpiar", mode: .newTab, searchSuggestions: [])
        XCTAssertTrue(spanish.contains { $0.action == .command(.clearTodayTabs) })
    }

    func testPageCommandsNeedAPage() {
        let (browser, _) = makeBrowser()
        let suggestions = browser.suggestions(for: "copiar", mode: .newTab, searchSuggestions: [])
        XCTAssertFalse(suggestions.contains { $0.action == .command(.copyURL) })
    }

    func testClearingSiteDataTargetsOnlyThatHost() async throws {
        let (browser, engine) = makeBrowser()
        browser.openTab(URL(string: "https://mail.google.com/inbox"))

        browser.perform(.clearSiteCookiesAndRefresh)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(engine.clearedData.first?.1, "mail.google.com")
        XCTAssertEqual(engine.clearedData.first?.0, .cookiesAndSiteData)
    }

    func testClearTodayTabsArchivesThem() {
        let (browser, _) = makeBrowser()
        browser.openTab(URL(string: "https://a.com"))
        let kept = browser.openTab(URL(string: "https://b.com"))

        browser.perform(.clearUnselectedTodayTabs)
        XCTAssertEqual(browser.activeSpace.tabs.map(\.id), [kept.id])

        browser.perform(.clearTodayTabs)
        XCTAssertTrue(browser.activeSpace.tabs.isEmpty)
        XCTAssertEqual(browser.archive.count, 2)
    }

    func testArchiveTabsBelowAndDuplicate() {
        let (browser, _) = makeBrowser()
        let a = browser.openTab(URL(string: "https://a.com"))
        browser.openTab(URL(string: "https://b.com"))
        let c = browser.openTab(URL(string: "https://c.com"))
        // Orden: c, b, a.
        browser.select(c)
        browser.perform(.archiveTabsBelow)
        XCTAssertEqual(browser.activeSpace.tabs.map(\.id), [c.id])
        XCTAssertFalse(browser.activeSpace.tabs.contains { $0.id == a.id })

        browser.perform(.duplicateTab)
        XCTAssertEqual(browser.activeSpace.tabs.map { $0.url?.host() }, ["c.com", "c.com"])
        XCTAssertEqual(browser.activeSpace.tabs.first?.id, c.id, "La copia va justo debajo")
    }

    func testRenamingATabAndCollapsingPinned() {
        let (browser, _) = makeBrowser()
        let tab = browser.openTab(URL(string: "https://a.com"))

        browser.rename(tab, to: "Mi correo")
        XCTAssertEqual(tab.displayTitle, "Mi correo")
        browser.rename(tab, to: "  ")
        XCTAssertNil(tab.customTitle)

        let space = browser.activeSpace
        browser.perform(.togglePinnedSection)
        XCTAssertTrue(space.isPinnedCollapsed)
    }

    func testMoveTabToAnotherSpace() {
        let (browser, _) = makeBrowser()
        let tab = browser.openTab(URL(string: "https://a.com"))
        let target = browser.spaces[1]

        let suggestions = browser.suggestions(for: "mover", mode: .newTab, searchSuggestions: [])
        let move = suggestions.first { $0.action == .moveTabToSpace(target.id) }
        XCTAssertNotNil(move)

        browser.perform(move!, mode: .newTab)
        XCTAssertEqual(browser.activeSpaceID, target.id)
        XCTAssertEqual(browser.selectedTab?.id, tab.id)
    }
}
