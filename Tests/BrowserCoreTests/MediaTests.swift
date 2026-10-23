import XCTest
import BrowserEngine
@testable import BrowserCore

@MainActor
final class MediaTests: XCTestCase {
    private func makeBrowser() -> (Browser, FakeEngine) {
        let engine = FakeEngine()
        let browser = Browser(engine: engine, store: nil, historyFileURL: nil, importFromArc: false,
                              defaults: UserDefaults(suiteName: UUID().uuidString)!, startsBackgroundWork: false)
        return (browser, engine)
    }

    private let playingVideo = MediaState(isPlaying: true, isMuted: false, hasVideo: true, isInPictureInPicture: false)

    func testSwitchingAwayFromAPlayingVideoEntersPictureInPictureAndComingBackExits() throws {
        let (browser, _) = makeBrowser()
        let video = browser.openTab(URL(string: "https://youtube.com/watch"))
        let videoPage = try XCTUnwrap(video.page as? FakePage)
        videoPage.onMediaChange?(playingVideo)

        let other = browser.openTab(URL(string: "https://a.com"))
        XCTAssertEqual(videoPage.pictureInPicture, [true], "Al irse de la pestaña, el vídeo pasa a PiP")
        XCTAssertEqual(browser.backgroundMediaTabs.map(\.id), [video.id])

        videoPage.onMediaChange?(MediaState(isPlaying: true, isMuted: false, hasVideo: true, isInPictureInPicture: true))
        browser.select(video)
        XCTAssertEqual(videoPage.pictureInPicture, [true, false], "Al volver, sale de PiP")
        _ = other
    }

    func testReturnToTabButtonInPictureInPictureRevealsTheTab() throws {
        let (browser, _) = makeBrowser()
        let video = browser.openTab(URL(string: "https://youtube.com/watch"))
        let videoPage = try XCTUnwrap(video.page as? FakePage)
        videoPage.onMediaChange?(playingVideo)
        browser.openTab(URL(string: "https://a.com"))
        videoPage.onMediaChange?(MediaState(isPlaying: true, isMuted: false, hasVideo: true, isInPictureInPicture: true))

        // El PiP del sistema devuelve el vídeo a la página y sigue sonando.
        videoPage.onMediaChange?(playingVideo)

        XCTAssertEqual(browser.selectedTab?.id, video.id)
    }

    func testTabsWithMediaAreNotHibernatedAndCanBeDismissed() throws {
        let (browser, _) = makeBrowser()
        let music = browser.openTab(URL(string: "https://music.com"))
        (music.page as? FakePage)?.onMediaChange?(
            MediaState(isPlaying: true, isMuted: false, hasVideo: false, isInPictureInPicture: false)
        )
        browser.openTab(URL(string: "https://a.com"))

        browser.hibernateIdleTabs(now: Date().addingTimeInterval(browser.hibernateAfter + 1))
        XCTAssertFalse(music.isHibernated, "No se corta la música")

        browser.dismissMedia(of: music)
        XCTAssertTrue(browser.backgroundMediaTabs.isEmpty)
        XCTAssertEqual((music.page as? FakePage)?.mediaCommands.count, 1)
    }

    func testAutomaticPictureInPictureCanBeTurnedOff() throws {
        let (browser, _) = makeBrowser()
        browser.autoPictureInPicture = false
        let video = browser.openTab(URL(string: "https://youtube.com/watch"))
        let videoPage = try XCTUnwrap(video.page as? FakePage)
        videoPage.onMediaChange?(playingVideo)

        browser.openTab(URL(string: "https://a.com"))
        XCTAssertTrue(videoPage.pictureInPicture.isEmpty)
    }
}
