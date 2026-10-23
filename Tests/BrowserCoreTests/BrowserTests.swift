import AppKit
import XCTest
import BrowserEngine
@testable import BrowserCore

@MainActor
final class FakePage: WebPage {
    let view = NSView()
    var onChange: (@MainActor (WebPageSnapshot) -> Void)?
    var interactionState: Any? { "historial" }
    var zoom: Double = 1
    private(set) var loadedURLs: [URL] = []
    private(set) var restoredState: Any?

    func load(_ url: URL) { loadedURLs.append(url) }
    func restore(interactionState: Any) { restoredState = interactionState }
    func goBack() {}
    func goForward() {}
    func reload() {}
    func stopLoading() {}
}

@MainActor
final class FakeEngine: WebEngine {
    private(set) var pages: [FakePage] = []

    func makePage() -> WebPage {
        let page = FakePage()
        pages.append(page)
        return page
    }
}

@MainActor
final class BrowserTests: XCTestCase {
    private func makeBrowser(store: SidebarStore? = nil) -> (Browser, FakeEngine) {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: store, importFromArc: false, startsBackgroundWork: false)
        return (browser, engine)
    }

    func testIdleTabsHibernateButVisibleTabStaysAwake() {
        let (browser, _) = makeBrowser()
        let old = browser.openTab(URL(string: "https://a.com"))
        let visible = browser.openTab(URL(string: "https://b.com"))

        browser.hibernateIdleTabs(now: Date().addingTimeInterval(browser.hibernateAfter + 1))

        XCTAssertTrue(old.isHibernated)
        XCTAssertFalse(visible.isHibernated)
    }

    func testWakingRestoresHistoryInsteadOfReloading() throws {
        let (browser, engine) = makeBrowser()
        let tab = browser.openTab(URL(string: "https://a.com"))
        browser.openTab(URL(string: "https://b.com"))
        browser.hibernateBackgroundTabs()

        browser.select(tab)

        let page = try XCTUnwrap(engine.pages.last)
        XCTAssertEqual(page.restoredState as? String, "historial")
        XCTAssertTrue(page.loadedURLs.isEmpty)
    }

    func testClosingTabArchivesItAndPinnedTabsAreOnlyUnloaded() {
        let (browser, _) = makeBrowser()
        let pinned = browser.openTab(URL(string: "https://pinned.com"))
        browser.togglePin(pinned)
        let normal = browser.openTab(URL(string: "https://normal.com"))

        browser.close(normal)
        browser.close(pinned)

        XCTAssertEqual(browser.archive.map(\.url.host), ["normal.com"])
        XCTAssertTrue(browser.activeSpace.isPinned(pinned))
        XCTAssertTrue(pinned.isHibernated)

        browser.reopenLastClosedTab()
        XCTAssertEqual(browser.selectedTab?.url?.host(), "normal.com")
        XCTAssertTrue(browser.archive.isEmpty)
    }

    func testFoldersAndFavorites() {
        let (browser, _) = makeBrowser()
        let tab = browser.openTab(URL(string: "https://a.com"))
        let folder = browser.newFolder(named: "Coding")

        browser.move(tab, to: folder)
        XCTAssertEqual(folder.tabs.map(\.id), [tab.id])
        XCTAssertTrue(browser.activeSpace.tabs.isEmpty)

        browser.addToFavorites(tab)
        XCTAssertTrue(folder.tabs.isEmpty)
        XCTAssertTrue(browser.isFavorite(tab))
    }

    func testSidebarIsSavedAndRestoredWithoutLoadingTabs() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SidebarStore(fileURL: directory.appending(path: "Sidebar.json"))

        let (browser, _) = makeBrowser(store: store)
        let favorite = browser.openTab(URL(string: "https://fav.com"))
        browser.addToFavorites(favorite)
        let folder = browser.newFolder(named: "Merch")
        browser.move(browser.openTab(URL(string: "https://shop.com")), to: folder)
        browser.openTab(URL(string: "https://today.com"))
        browser.saveNow()

        let (restored, engine) = makeBrowser(store: store)

        XCTAssertEqual(restored.favorites.map(\.url?.host), ["fav.com"])
        XCTAssertEqual(restored.activeSpace.folders.first?.name, "Merch")
        XCTAssertEqual(restored.activeSpace.folders.first?.tabs.first?.url?.host(), "shop.com")
        XCTAssertEqual(restored.selectedTab?.url?.host(), "today.com")
        // Solo se carga la pestaña visible.
        XCTAssertEqual(engine.pages.count, 1)
    }

    func testDragAndDropMovesTabsBetweenSections() {
        let (browser, _) = makeBrowser()
        let a = browser.openTab(URL(string: "https://a.com"))
        let b = browser.openTab(URL(string: "https://b.com"))
        let c = browser.openTab(URL(string: "https://c.com"))
        XCTAssertEqual(browser.activeSpace.tabs.map(\.id), [c.id, b.id, a.id])

        // Bajar «c» debajo de «a» dentro de la misma lista.
        browser.move(c, to: .today(3))
        XCTAssertEqual(browser.activeSpace.tabs.map(\.id), [b.id, a.id, c.id])

        let folder = browser.newFolder(named: "Coding")
        browser.move(a, to: .folder(folder, 0))
        browser.move(b, to: .favorites(0))
        browser.move(c, to: .pinned(0))
        XCTAssertEqual(folder.tabs.map(\.id), [a.id])
        XCTAssertEqual(browser.favorites.map(\.id), [b.id])
        XCTAssertEqual(browser.activeSpace.pinned.map(\.id), [c.id, folder.id])

        browser.move(folder, toPinnedIndex: 0)
        XCTAssertEqual(browser.activeSpace.pinned.map(\.id), [folder.id, c.id])
    }

    func testCommandBarSuggestsOpenTabsHistoryAndCommands() {
        let (browser, _) = makeBrowser()
        let tab = browser.openTab(URL(string: "https://github.com"))
        browser.history.record(url: URL(string: "http://localhost:3005/")!, title: "EQIDIS Facturación")
        browser.openTab(URL(string: "https://apple.com"))

        let tabs = browser.suggestions(for: "git", mode: .newTab, searchSuggestions: [])
        XCTAssertTrue(tabs.contains { $0.action == .switchToTab(tab.id) })

        let history = browser.suggestions(for: "eqidis", mode: .newTab, searchSuggestions: [])
        XCTAssertEqual(history.first { $0.id.hasPrefix("history:") }?.detail, "localhost:3005")

        let commands = browser.suggestions(for: "copiar", mode: .currentTab, searchSuggestions: [])
        XCTAssertTrue(commands.contains { $0.action == .command(.copyURL) })

        let search = browser.suggestions(for: "mejor navegador", mode: .newTab, searchSuggestions: ["mejor navegador mac"])
        XCTAssertEqual(search.first?.detail, "Buscar en Google")
        XCTAssertTrue(search.contains { $0.title == "mejor navegador mac" })
    }

    func testCommandBarOpensInNewTabOrCurrentTab() {
        let (browser, _) = makeBrowser()
        let current = browser.openTab(URL(string: "https://a.com"))
        let url = URL(string: "https://b.com")!

        browser.perform(Suggestion(id: "x", title: "b", action: .open(url)), mode: .currentTab)
        XCTAssertEqual(browser.activeSpace.tabs.count, 1)
        XCTAssertEqual(current.page.map { ($0 as! FakePage).loadedURLs.last }, url)

        browser.newTab()
        XCTAssertEqual(browser.commandBar, .newTab)
        browser.perform(Suggestion(id: "x", title: "b", action: .open(url)), mode: .newTab)
        XCTAssertNil(browser.commandBar)
        XCTAssertEqual(browser.activeSpace.tabs.count, 2)
    }

    func testImportsArcThemeColors() {
        let customInfo: [String: Any] = ["windowTheme": [
            "background": ["single": ["_0": [
                "contentOverBackgroundAppearance": "dark",
                "style": ["color": ["_0": ["blendedSingleColor": ["_0": [
                    "modifiers": ["overlay": "grain", "noiseFactor": 0.3],
                    "color": ["red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 1.0],
                ]]]]],
            ]]],
            "semanticColorPalette": ["appearanceBased": ["dark": [
                "hover": ["red": 0.34, "green": 0.4, "blue": 0.5, "alpha": 0.48],
                "focus": ["red": 0.27, "green": 0.34, "blue": 0.45, "alpha": 0.8],
            ]]],
        ]]

        let theme = ArcImporter.theme(from: customInfo, fallback: .ember)

        XCTAssertEqual(theme.background, [SpaceColor(red: 0.1, green: 0.2, blue: 0.3)])
        XCTAssertEqual(theme.grain, 0.3)
        XCTAssertTrue(theme.isDark)
        XCTAssertEqual(theme.hover, SpaceColor(red: 0.34, green: 0.4, blue: 0.5, alpha: 0.48))
        XCTAssertEqual(theme.focus.alpha, 0.8)
    }

    func testImportsArcSidebar() throws {
        let json = """
        {"sidebar": {"containers": [{"global": {}}, {
          "topAppsContainerIDs": [{"default": true}, "FAV"],
          "spaces": ["S1", {"id": "S1", "title": "Life",
                            "containerIDs": ["unpinned", "U1", "pinned", "P1"],
                            "customInfo": {"iconType": {"icon": "planet"},
                                           "windowTheme": {"background": {"red": 0.1, "green": 0.2, "blue": 0.3}}}}],
          "items": [
            "FAV", {"id": "FAV", "childrenIds": ["T1"], "data": {"itemContainer": {}}},
            "T1", {"id": "T1", "childrenIds": [], "data": {"tab": {"savedURL": "https://youtube.com", "savedTitle": "YouTube"}}},
            "P1", {"id": "P1", "childrenIds": ["F1"], "data": {"itemContainer": {}}},
            "F1", {"id": "F1", "title": "Coding", "childrenIds": ["T2"], "data": {"list": {}}},
            "T2", {"id": "T2", "title": "Mi repo", "childrenIds": [], "data": {"tab": {"savedURL": "https://github.com", "savedTitle": "GitHub"}}},
            "U1", {"id": "U1", "childrenIds": ["T3"], "data": {"itemContainer": {}}},
            "T3", {"id": "T3", "childrenIds": [], "data": {"tab": {"savedURL": "https://apple.com", "savedTitle": "Apple"}}}
          ]}]}}
        """
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = try ArcImporter.load(from: file)

        XCTAssertEqual(snapshot.favorites.map(\.title), ["YouTube"])
        let space = try XCTUnwrap(snapshot.spaces.first)
        XCTAssertEqual(space.name, "Life")
        XCTAssertEqual(space.icon, "globe.americas")
        XCTAssertEqual(space.theme.background, [SpaceColor(red: 0.1, green: 0.2, blue: 0.3)])
        guard case .folder(let folder) = space.pinned.first else { return XCTFail("Se esperaba una carpeta") }
        XCTAssertEqual(folder.name, "Coding")
        XCTAssertEqual(folder.tabs.map(\.title), ["Mi repo"])
        XCTAssertEqual(space.tabs.map(\.url?.host), ["apple.com"])
    }
}
