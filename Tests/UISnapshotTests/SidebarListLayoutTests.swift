import AppKit
import XCTest
@testable import BrowserCore
@testable import BrowserEngine
@testable import BrowserUI
@testable import SidebarFeature

@MainActor
final class SidebarListLayoutTests: XCTestCase {
    private final class NoEngine: WebEngine {
        func makePage(profile: UUID?) -> WebPage { fatalError("No se usan páginas") }
        func removeProfileData(_ profile: UUID) {}
        func clearBrowsingData(_ kinds: BrowsingData, host: String?) async {}
        func importCookies(_ cookies: [HTTPCookie], profile: UUID?) async {}
    }

    /// Fijar una pestaña de Hoy quita una fila y pone otra en la misma animación: cada fila tiene
    /// que quedar con su altura (antes "Nueva pestaña" se quedaba con la del separador, aplastada).
    func testRowsKeepTheirHeightsWhenATabMovesBetweenSections() throws {
        let browser = Browser(engine: NoEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        let space = browser.activeSpace
        let make = { (title: String) in
            BrowserTab(url: URL(string: "https://\(title).example"), title: title) { _ in fatalError("No se usan páginas") }
        }
        space.pinned = [.tab(make("fijada"))]
        space.tabs = (0..<4).map { make("hoy\($0)") }

        let (table, coordinator, window) = makeList(browser: browser, space: space)
        defer { coordinator.detach(); window.close() }
        assertHeights(table, coordinator, "al empezar")

        browser.togglePin(space.tabs[2])
        settle()
        assertHeights(table, coordinator, "al fijar")

        browser.togglePin(try XCTUnwrap(space.pinnedTabs.last))
        settle()
        assertHeights(table, coordinator, "al desfijar")
    }

    /// Una fila que AppKit dejó oculta tras un arrastre (altura 0) vuelve a verse al cambiar la lista
    /// o al pasar el ratón.
    func testHiddenRowsComeBack() throws {
        let browser = Browser(engine: NoEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        let space = browser.activeSpace
        let make = { (title: String) in
            BrowserTab(url: URL(string: "https://\(title).example"), title: title) { _ in fatalError("No se usan páginas") }
        }
        space.pinned = [.tab(make("fijada"))]
        space.tabs = (0..<3).map { make("hoy\($0)") }
        let (table, coordinator, window) = makeList(browser: browser, space: space)
        defer { coordinator.detach(); window.close() }

        let newTabRow = 3 // cabecera, fijada, separador, "Nueva pestaña"
        XCTAssertTrue(coordinator.tableView(table, viewFor: nil, row: newTabRow) is NewTabCellView)
        table.hideRows(at: [newTabRow], withAnimation: [])
        coordinator.showHiddenRows()
        settle()
        assertHeights(table, coordinator, "al pasar el ratón")

        table.hideRows(at: [newTabRow + 1], withAnimation: [])
        space.tabs.append(make("otra"))
        settle()
        assertHeights(table, coordinator, "al cambiar la lista")
    }

    /// Cambios que llegan mientras la animación anterior sigue en marcha.
    func testRowsKeepTheirHeightsWithChangesDuringAnimations() throws {
        let browser = Browser(engine: NoEngine(), store: nil, historyFileURL: nil, importFromArc: false,
                              startsBackgroundWork: false)
        let space = browser.activeSpace
        let make = { (title: String) in
            BrowserTab(url: URL(string: "https://\(title).example"), title: title) { _ in fatalError("No se usan páginas") }
        }
        space.pinned = (0..<3).map { .tab(make("fijada\($0)")) }
        space.tabs = (0..<20).map { make("hoy\($0)") }
        let (table, coordinator, window) = makeList(browser: browser, space: space)
        defer { coordinator.detach(); window.close() }

        let steps: [() -> Void] = [
            { browser.togglePin(space.tabs[1]) },
            { space.tabs.remove(at: 0) },
            { browser.togglePinnedSection(space) },
            { space.tabs.insert(make("nueva"), at: 0) },
            { browser.togglePinnedSection(space) },
            { browser.togglePin(space.pinnedTabs[0]) },
            { space.tabs.removeLast(2) },
        ]
        for (index, step) in steps.enumerated() {
            step()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            _ = index
        }
        settle()
        assertHeights(table, coordinator, "tras cambios seguidos")
    }

    private func makeList(browser: Browser, space: Space) -> (SidebarTableView, SidebarListCoordinator, NSWindow) {
        let coordinator = SidebarListCoordinator(browser: browser, space: space, theme: .default)
        let table = SidebarTableView()
        table.coordinator = coordinator
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.usesAutomaticRowHeights = false
        table.dataSource = coordinator
        table.delegate = coordinator
        let scroll = SidebarScrollView(frame: CGRect(x: 0, y: 0, width: 240, height: 260))
        scroll.documentView = table
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        table.frame = CGRect(x: 0, y: 0, width: 240, height: 600)
        coordinator.attach(table: table, scrollView: scroll, drag: SidebarDrag())
        settle()
        return (table, coordinator, window)
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    }

    private func assertHeights(_ table: NSTableView, _ coordinator: SidebarListCoordinator, _ moment: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(table.numberOfRows, coordinator.numberOfRows(in: table), moment, file: file, line: line)
        XCTAssertEqual(table.hiddenRowIndexes, [], moment, file: file, line: line)
        for row in 0..<table.numberOfRows {
            let expected = coordinator.tableView(table, heightOfRow: row) + table.intercellSpacing.height
            XCTAssertEqual(table.rect(ofRow: row).height, expected, "fila \(row) \(moment)", file: file, line: line)
            // La vista de cada fila es la de su tipo: la que daría la tabla si se pintara de cero.
            guard let shown = table.view(atColumn: 0, row: row, makeIfNecessary: false),
                  let fresh = coordinator.tableView(table, viewFor: nil, row: row) else { continue }
            XCTAssertTrue(type(of: shown) == type(of: fresh), "fila \(row) \(moment): \(type(of: shown)) en vez de \(type(of: fresh))",
                          file: file, line: line)
        }
    }
}
