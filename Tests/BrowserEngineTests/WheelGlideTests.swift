import XCTest
@testable import BrowserEngine

final class WheelGlideTests: XCTestCase {
    /// Un clic de la rueda recorre exactamente su distancia, en pasos que se van frenando, como un
    /// gesto del trackpad (empieza, cambia, termina), y dura alrededor de un cuarto de segundo.
    func testOneNotchGlidesItsWholeDistance() throws {
        var glide = WheelGlide()
        glide.add(dx: 0, dy: -40)
        var steps: [WheelGlide.Step] = []
        while let step = glide.step(elapsed: 1.0 / 120) { steps.append(step) }

        XCTAssertEqual(steps.first?.phase, .began)
        XCTAssertEqual(steps.last, WheelGlide.Step(dx: 0, dy: 0, phase: .ended))
        XCTAssertTrue(steps.dropFirst().dropLast().allSatisfy { $0.phase == .changed })
        XCTAssertEqual(steps.reduce(0) { $0 + $1.dy }, -40)
        XCTAssertGreaterThan(abs(steps[0].dy), abs(steps[steps.count - 2].dy))
        XCTAssertEqual(Double(steps.count) / 120, 0.25, accuracy: 0.1)
    }

    /// Clics seguidos se suman al recorrido que queda; al cambiar de sentido, lo pendiente se olvida.
    func testNotchesAccumulateAndReversingDropsTheRest() {
        var glide = WheelGlide()
        glide.add(dx: 0, dy: 40)
        let first = glide.step(elapsed: 1.0 / 120)?.dy ?? 0
        glide.add(dx: 0, dy: 40)
        var total = first
        while let step = glide.step(elapsed: 1.0 / 120) { total += step.dy }
        XCTAssertEqual(total, 80)

        glide.add(dx: 0, dy: 40)
        _ = glide.step(elapsed: 1.0 / 120)
        glide.add(dx: 0, dy: -40)
        total = 0
        while let step = glide.step(elapsed: 1.0 / 120) { total += step.dy }
        XCTAssertEqual(total, -40)
    }

    func testFinishEndsAGlideInProgressOnlyOnce() {
        var glide = WheelGlide()
        XCTAssertNil(glide.finish())
        glide.add(dx: 40, dy: 0)
        XCTAssertEqual(glide.step(elapsed: 1.0 / 60)?.phase, .began)
        XCTAssertEqual(glide.finish()?.phase, .ended)
        XCTAssertNil(glide.finish())
        XCTAssertNil(glide.step(elapsed: 1.0 / 60))
    }
}
