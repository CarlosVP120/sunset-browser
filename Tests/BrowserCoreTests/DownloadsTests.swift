import XCTest
@testable import BrowserEngine

@MainActor
final class DownloadsTests: XCTestCase {
    private func registry(_ records: [DownloadRecord]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try JSONEncoder().encode(records).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func record(_ name: String, state: DownloadRecord.State, daysAgo: Double = 0) -> DownloadRecord {
        DownloadRecord(id: UUID(), filename: name, fileURL: URL(filePath: "/tmp/no-existe/\(name)"),
                       sourceURL: URL(string: "https://www.eqidis.com/archivo"),
                       date: Date().addingTimeInterval(-daysAgo * 86_400), totalBytes: nil, state: state)
    }

    func testRestoresHistoryAndMarksInterruptedDownloadsAsFailed() throws {
        let url = try registry([record("a.pdf", state: .finished), record("b.zip", state: .inProgress)])

        let manager = DownloadManager(registryURL: url)

        XCTAssertEqual(manager.items.map(\.state), [.finished, .failed])
        XCTAssertNil(manager.overallProgress)
        XCTAssertEqual(manager.items[0].sourceHost, "eqidis.com")
        XCTAssertFalse(manager.items[0].fileExists)
    }

    func testRemovingFromTheListKeepsTheRest() throws {
        let url = try registry([record("a.pdf", state: .finished), record("b.png", state: .finished)])
        let manager = DownloadManager(registryURL: url)

        manager.removeFromList(manager.items[0])

        XCTAssertEqual(manager.items.map(\.filename), ["b.png"])
        let reloaded = DownloadManager(registryURL: url)
        XCTAssertEqual(reloaded.items.map(\.filename), ["b.png"], "Se guarda en disco")
    }
}
