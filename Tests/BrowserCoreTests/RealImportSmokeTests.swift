import XCTest
@testable import BrowserImport

/// Comprueba los lectores con los navegadores reales de este Mac (solo cuenta marcadores e
/// historial; no lee contraseñas ni cookies). Solo corre con SUNSET_REAL_IMPORT=1.
final class RealImportSmokeTests: XCTestCase {
    func testReadsInstalledBrowsers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SUNSET_REAL_IMPORT"] == "1")
        for source in ImportSource.available {
            let data = await BrowserImporter.read(source, kinds: [.sidebar, .bookmarks, .history])
            print("[\(source.name)] perfiles: \(source.chromium?.profiles().count ?? 0) · espacios: \(data.sidebar?.spaces.count ?? 0) · marcadores: \(data.bookmarks.count) · historial: \(data.history.count) · problemas: \(data.problems)")
        }
    }
}
