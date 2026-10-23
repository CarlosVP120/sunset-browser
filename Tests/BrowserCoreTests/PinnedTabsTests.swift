import XCTest
import BrowserEngine
@testable import BrowserCore

/// Fijadas y favoritas como en Arc: guardan su dirección, marcan "/" al moverse, vuelven al
/// cerrarlas y escribir otra dirección abre una pestaña nueva.
@MainActor
final class PinnedTabsTests: XCTestCase {
    private func makeBrowser() -> Browser {
        Browser(engine: FakeEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                defaults: UserDefaults(suiteName: UUID().uuidString)!, startsBackgroundWork: false)
    }

    /// Simula que la página navegó a otra dirección.
    private func navigate(_ tab: BrowserTab, to url: String) {
        let page = tab.wake() as! FakePage
        page.onChange?(WebPageSnapshot(title: "Página", url: URL(string: url), faviconURL: nil, isLoading: false,
                                       progress: 1, canGoBack: true, canGoForward: false))
    }

    func testPinningRemembersURLAndMarksWhenAway() {
        let browser = makeBrowser()
        let tab = browser.openTab(URL(string: "https://mail.google.com/mail/u/0/"))
        XCTAssertNil(tab.pinnedURL)

        browser.togglePin(tab)
        XCTAssertEqual(tab.pinnedURL?.absoluteString, "https://mail.google.com/mail/u/0/")
        XCTAssertFalse(tab.isAwayFromPinned)

        // Abrir un correo (cambia el ancla) no cuenta como irse.
        navigate(tab, to: "https://mail.google.com/mail/u/0#inbox/123")
        XCTAssertFalse(tab.isAwayFromPinned)

        navigate(tab, to: "https://mail.google.com/mail/u/0/settings")
        XCTAssertTrue(tab.isAwayFromPinned)

        browser.togglePin(tab) // desfijar
        XCTAssertNil(tab.pinnedURL)
        XCTAssertFalse(tab.isAwayFromPinned)
    }

    func testClosingAPinnedTabReturnsToItsURL() {
        let browser = makeBrowser()
        let tab = browser.openTab(URL(string: "https://x.com/home"))
        browser.togglePin(tab)
        navigate(tab, to: "https://x.com/someone/status/1")
        XCTAssertTrue(tab.isAwayFromPinned)

        browser.close(tab)
        XCTAssertTrue(tab.isHibernated)
        XCTAssertTrue(browser.activeSpace.isPinned(tab)) // sigue fijada
        XCTAssertEqual(tab.url?.absoluteString, "https://x.com/home")
        XCTAssertFalse(tab.isAwayFromPinned)
    }

    func testClosingAFavoriteReturnsToItsURL() {
        let browser = makeBrowser()
        let tab = browser.openTab(URL(string: "https://github.com/"))
        browser.addToFavorites(tab)
        navigate(tab, to: "https://github.com/apple/swift")
        browser.close(tab)
        XCTAssertEqual(tab.url?.absoluteString, "https://github.com/")
        XCTAssertTrue(browser.isFavorite(tab))
    }

    func testTypingAnotherSiteInAPinnedTabOpensANewTab() {
        let browser = makeBrowser()
        let gmail = browser.openTab(URL(string: "https://mail.google.com/"))
        browser.addToFavorites(gmail)
        browser.select(gmail)

        browser.navigate(to: "asdasd") // búsqueda en google.com: otro sitio
        XCTAssertNotEqual(browser.selectedTab?.id, gmail.id)
        XCTAssertEqual(browser.selectedTab?.url?.host(), "www.google.com")
        XCTAssertEqual(gmail.url?.host(), "mail.google.com")
        XCTAssertFalse((gmail.page as! FakePage).loadedURLs.contains { $0.host() == "www.google.com" })

        // Dentro del mismo sitio sí navega en la propia fijada.
        browser.select(gmail)
        browser.navigate(to: "https://mail.google.com/mail/u/1/")
        XCTAssertEqual(browser.selectedTab?.id, gmail.id)
        XCTAssertEqual((gmail.page as! FakePage).loadedURLs.last?.absoluteString, "https://mail.google.com/mail/u/1/")
    }

    func testNormalTabsStillNavigateInPlace() {
        let browser = makeBrowser()
        let tab = browser.openTab(URL(string: "https://a.com"))
        browser.navigate(to: "https://b.com")
        XCTAssertEqual(browser.selectedTab?.id, tab.id)
    }

    func testPinnedURLIsSavedAndRestored() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pinned-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SidebarStore(fileURL: file)
        let browser = Browser(engine: FakeEngine(), store: store, historyFileURL: nil, importFromArc: false,
                              defaults: UserDefaults(suiteName: UUID().uuidString)!, startsBackgroundWork: false)
        let tab = browser.openTab(URL(string: "https://notion.so/home"))
        browser.togglePin(tab)
        navigate(tab, to: "https://notion.so/page-123")
        browser.saveNow()

        let reopened = Browser(engine: FakeEngine(), store: store, historyFileURL: nil, importFromArc: false,
                               defaults: UserDefaults(suiteName: UUID().uuidString)!, startsBackgroundWork: false)
        let restored = try XCTUnwrap(reopened.tab(withID: tab.id))
        XCTAssertEqual(restored.pinnedURL?.absoluteString, "https://notion.so/home")
        XCTAssertTrue(restored.isAwayFromPinned)
    }
}
