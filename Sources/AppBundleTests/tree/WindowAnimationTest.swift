@testable import AppBundle
import XCTest

final class WindowAnimationTest: XCTestCase {
    func testFrameTimingAccountsForWorkAndSkipsMissedFrames() {
        XCTAssertEqual(windowAnimationFrameDelay(elapsed: 0.010, framesPerSecond: 60), 1.0 / 60 - 0.010, accuracy: 0.000001)
        XCTAssertEqual(windowAnimationFrameDelay(elapsed: 0.025, framesPerSecond: 60), 2.0 / 60 - 0.025, accuracy: 0.000001)
        XCTAssertEqual(windowAnimationFrameDelay(elapsed: 0.010, framesPerSecond: 120), 2.0 / 120 - 0.010, accuracy: 0.000001)
    }

    @MainActor func testAnimationsAreOptIn() {
        XCTAssertFalse(parseConfig("").config.enableWindowAnimations)
        let enabled = parseConfig("enable-window-animations = true")
        XCTAssertTrue(enabled.errors.isEmpty)
        XCTAssertTrue(enabled.config.enableWindowAnimations)
        XCTAssertFalse(parseConfig("enable-window-animations = 'true'").errors.isEmpty)
    }

    func testAnimationReachesExactFrameAndClampsProgress() {
        let start = CGRect(x: -1200, y: -200, width: 800, height: 600)
        let target = CGRect(x: 300, y: 100, width: 500, height: 400)
        for progress in [-1.0, 0] {
            XCTAssertEqual(animatedWindowFrame(from: start, to: target, progress: progress), start)
        }
        for progress in [1.0, 2] {
            XCTAssertEqual(animatedWindowFrame(from: start, to: target, progress: progress), target)
        }
    }

    func testMovementAndResizeAreMonotonicWithoutOvershoot() {
        let start = CGRect(x: -800, y: 300, width: 1000, height: 200)
        let target = CGRect(x: 200, y: -100, width: 400, height: 700)
        var previous = start
        for step in 1 ... 60 {
            let frame = animatedWindowFrame(from: start, to: target, progress: Double(step) / 60)
            XCTAssertGreaterThanOrEqual(frame.minX, previous.minX)
            XCTAssertLessThanOrEqual(frame.minX, target.minX)
            XCTAssertLessThanOrEqual(frame.minY, previous.minY)
            XCTAssertGreaterThanOrEqual(frame.minY, target.minY)
            XCTAssertLessThanOrEqual(frame.width, previous.width)
            XCTAssertGreaterThanOrEqual(frame.width, target.width)
            XCTAssertGreaterThanOrEqual(frame.height, previous.height)
            XCTAssertLessThanOrEqual(frame.height, target.height)
            previous = frame
        }
        XCTAssertEqual(previous, target)
    }
}
