@testable import AppBundle
import XCTest
import AppKit

final class WindowAnimationTest: XCTestCase {
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
            XCTAssertEqual(WindowFrameAnimation(from: start, to: target, at: 0).frame(at: progress * WindowFrameAnimation.duration), start)
        }
        for progress in [1.0, 2] {
            XCTAssertEqual(WindowFrameAnimation(from: start, to: target, at: 0).frame(at: progress * WindowFrameAnimation.duration), target)
        }
    }

    func testMovementAndResizeAreMonotonicWithoutOvershoot() {
        let start = CGRect(x: -800, y: 300, width: 1000, height: 200)
        let target = CGRect(x: 200, y: -100, width: 400, height: 700)
        var previous = start
        for step in 1 ... 60 {
            let frame = WindowFrameAnimation(from: start, to: target, at: 0).frame(at: Double(step) / 60 * WindowFrameAnimation.duration)
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

    func testRetargetPreservesPositionAndVelocityAndSettlesExactly() {
        let start = CGRect(x: 100, y: 200, width: 800, height: 600)
        let target = CGRect(x: 500, y: 100, width: 1000, height: 400)
        let first = WindowFrameAnimation(from: start, to: target, at: 10)
        let time = 10.06
        let position = first.frame(at: time)
        let next = WindowFrameAnimation(from: position, to: start, at: time, replacing: first)
        XCTAssertEqual(next.frame(at: time), position)
        XCTAssertEqual(next.velocity(at: time), first.velocity(at: time))
        // Compare visible displacement around the retarget, independent of the derivative helper.
        let delta = 0.00001
        let before = first.frame(at: time - delta)
        let after = next.frame(at: time + delta)
        XCTAssertEqual((position.origin.x - before.origin.x) / delta,
                       (after.origin.x - position.origin.x) / delta, accuracy: 2)
        XCTAssertEqual((position.width - before.width) / delta,
                       (after.width - position.width) / delta, accuracy: 2)
        XCTAssertEqual(next.frame(at: time + 1), start)
        XCTAssertEqual(next.velocity(at: time + 1), .zero)
    }

    func testExpiredAnimationDoesNotCarryStaleVelocity() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 100, y: 0, width: 200, height: 100)
        let previous = WindowFrameAnimation(from: start, to: target, at: 0)
        let next = WindowFrameAnimation(from: target, to: start, at: 1, replacing: previous)
        XCTAssertEqual(next.velocity(at: 1), .zero)
        XCTAssertEqual(next.frame(at: 2), start)
    }

    @MainActor func testDisplayClockStopsAfterCancellation() async throws {
        let ticked = expectation(description: "Received display ticks")
        var count = 0
        let clock = DisplayFrameClock(screen: NSScreen.main) {
            count += 1
            if count == 2 { ticked.fulfill() }
        }
        defer { clock.stop() }
        await fulfillment(of: [ticked], timeout: 2)
        clock.stop()
        let stoppedCount = count
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(count, stoppedCount)
    }

    @MainActor func testFallbackClockCanPauseResumeAndStop() async throws {
        let ticked = expectation(description: "Fallback ticks")
        var count = 0
        let clock = DisplayFrameClock(screen: nil) {
            count += 1
            if count == 2 { ticked.fulfill() }
        }
        defer { clock.stop() }
        await fulfillment(of: [ticked], timeout: 2)
        clock.setPaused(true)
        let pausedCount = count
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(count, pausedCount)
        clock.setPaused(false)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThan(count, pausedCount)
        clock.stop()
        let stoppedCount = count
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(count, stoppedCount)
    }

    @MainActor func testLastAnimationSubscriberReleasesClockAndOldCancellationDoesNotStopReplacement() {
        let (stopFirst, _) = DisplayFrameClock.frames(screen: nil)
        let (stopSecond, _) = DisplayFrameClock.frames(screen: nil)
        defer { stopFirst(); stopSecond() }
        weak let clock = DisplayFrameClock.animationClocks[nil]
        XCTAssertNotNil(clock)
        stopFirst()
        XCTAssertTrue(DisplayFrameClock.animationClocks[nil] === clock)
        stopSecond()
        XCTAssertNil(DisplayFrameClock.animationClocks[nil])
        XCTAssertNil(clock, "The run-loop resources must also release their clock target")

        let (stopReplacement, _) = DisplayFrameClock.frames(screen: nil)
        defer { stopReplacement() }
        weak let replacement = DisplayFrameClock.animationClocks[nil]
        XCTAssertNotNil(replacement)
        stopFirst()
        stopSecond()
        XCTAssertTrue(DisplayFrameClock.animationClocks[nil] === replacement)
        stopReplacement()
        XCTAssertNil(replacement)
    }

    @MainActor func testSlowAnimationConsumerSkipsOldTicksAndOtherConsumerSurvivesCancellation() async throws {
        // Stream buffering must be testable even while the display is asleep.
        let (stopFirst, first) = DisplayFrameClock.frames(screen: nil)
        let (stopSecond, second) = DisplayFrameClock.frames(screen: nil)
        defer { stopFirst(); stopSecond() }
        var firstTicks = first.makeAsyncIterator()
        var secondTicks = second.makeAsyncIterator()
        let initial = await firstTicks.next()!
        try await Task.sleep(for: .milliseconds(100))
        let latest = await firstTicks.next()!
        XCTAssertGreaterThan(latest - initial, 0.05)
        stopFirst()
        let remainingTick = await secondTicks.next()
        XCTAssertNotNil(remainingTick)
        stopSecond()
    }
}
