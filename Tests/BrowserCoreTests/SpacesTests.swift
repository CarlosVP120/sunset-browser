import XCTest
@testable import BrowserCore

@MainActor
final class SpacesTests: XCTestCase {
    private func makeBrowser() -> (Browser, FakeEngine) {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        return (browser, engine)
    }

    func testTabsOfASpaceUseItsProfile() {
        let (browser, engine) = makeBrowser()
        let work = browser.addProfile(named: "Trabajo")
        let space = browser.activeSpace
        browser.setProfile(work.id, for: space)

        browser.openTab(URL(string: "https://mail.google.com"))

        XCTAssertEqual(engine.profiles.last, work.id)
        XCTAssertEqual(browser.profileName(space.profileID), "Trabajo")

        browser.deleteProfile(work)
        XCTAssertNil(space.profileID)
        XCTAssertTrue(browser.profiles.isEmpty)
    }

    func testDeletingASpaceArchivesItsTabs() {
        let (browser, _) = makeBrowser()
        let doomed = browser.activeSpace
        browser.openTab(URL(string: "https://a.com"))

        browser.delete(doomed)

        XCTAssertFalse(browser.spaces.contains { $0.id == doomed.id })
        XCTAssertEqual(browser.archive.first?.url.host(), "a.com")
        XCTAssertNotEqual(browser.activeSpaceID, doomed.id)

        // El último espacio no se puede borrar.
        browser.delete(browser.spaces[0])
        XCTAssertEqual(browser.spaces.count, 1)
    }

    func testExportCopiesTabsIntoAFolder() throws {
        let (browser, _) = makeBrowser()
        let source = browser.spaces[0], target = browser.spaces[1]
        browser.openTab(URL(string: "https://a.com"))
        browser.openTab(URL(string: "https://b.com"))

        browser.export(source, intoFolderIn: target)

        let folder = try XCTUnwrap(target.folders.first)
        XCTAssertEqual(folder.name, source.name)
        XCTAssertEqual(Set(folder.tabs.compactMap { $0.url?.host() }), ["a.com", "b.com"])
        XCTAssertEqual(source.tabs.count, 2, "Exportar copia, no mueve")
    }

    func testTabNavigationShortcuts() {
        let (browser, _) = makeBrowser()
        let a = browser.openTab(URL(string: "https://a.com"))
        let b = browser.openTab(URL(string: "https://b.com"))
        let c = browser.openTab(URL(string: "https://c.com"))
        // Orden en la barra: c, b, a (las nuevas van arriba).

        browser.selectTab(at: 0)
        XCTAssertEqual(browser.selectedTab?.id, c.id)
        browser.selectAdjacentTab(1)
        XCTAssertEqual(browser.selectedTab?.id, b.id)
        browser.selectLastTab()
        XCTAssertEqual(browser.selectedTab?.id, a.id)
        browser.selectAdjacentTab(1)
        XCTAssertEqual(browser.selectedTab?.id, c.id, "Da la vuelta")

        browser.selectRecentTab()
        XCTAssertEqual(browser.selectedTab?.id, a.id, "⌃Tab vuelve a la anterior")

        let first = browser.activeSpaceID
        browser.activateAdjacentSpace(1)
        XCTAssertNotEqual(browser.activeSpaceID, first)
        browser.activateAdjacentSpace(-1)
        XCTAssertEqual(browser.activeSpaceID, first)
    }

    func testReorderingSpaces() {
        let (browser, _) = makeBrowser()
        browser.addSpace(name: "Tercero")
        let names = browser.spaces.map(\.name)

        browser.moveSpaces(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(browser.spaces.map(\.name), [names[2], names[0], names[1]])
    }

    func testThemeGenerationFollowsAppearance() {
        let seed = SpaceColor(hue: 0.6, saturation: 0.8, brightness: 1)
        let dark = SpaceTheme.make(seeds: [seed], appearance: .dark, intensity: 0.5, grain: 0.3)
        let light = SpaceTheme.make(seeds: [seed], appearance: .light, intensity: 0.5, grain: 0.3)

        XCTAssertTrue(dark.isDark)
        XCTAssertLessThan(dark.background[0].hsb.brightness, 0.5)
        XCTAssertFalse(light.isDark)
        XCTAssertGreaterThan(light.background[0].hsb.brightness, 0.85)
        XCTAssertEqual(light.seeds, [seed])

        let auto = SpaceTheme.make(seeds: [seed], appearance: .auto, intensity: 0.5, grain: 0.3, systemIsDark: true)
        XCTAssertTrue(auto.isDark)
        XCTAssertFalse(auto.resolved(systemIsDark: false).isDark)
        XCTAssertTrue(dark.resolved(systemIsDark: false).isDark, "Un tema oscuro fijo no cambia")
    }

    func testHSBRoundTrip() {
        let color = SpaceColor(hue: 0.33, saturation: 0.7, brightness: 0.9)
        let hsb = color.hsb
        XCTAssertEqual(hsb.hue, 0.33, accuracy: 0.001)
        XCTAssertEqual(hsb.saturation, 0.7, accuracy: 0.001)
        XCTAssertEqual(hsb.brightness, 0.9, accuracy: 0.001)
    }

    func testOldThemesStillDecode() throws {
        let old = SpaceTheme.dark(from: .navy)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "seeds")
        json.removeValue(forKey: "appearance")
        json.removeValue(forKey: "intensity")

        let decoded = try JSONDecoder().decode(SpaceTheme.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.seeds.count, 1)
        XCTAssertEqual(decoded.background, old.background)
    }
}
