import AppKit
import QuartzCore

// Display ticks are lossy: a slow AX write must not build a backlog of frames.
@MainActor
final class DisplayFrameClock: NSObject {
    private static var animationClocks: [NSScreen?: DisplayFrameClock] = [:]
    private static var animationStreams: [NSScreen?: [UUID: AsyncStream<Double>.Continuation]] = [:]
    private var displayLink: AnyObject?
    private var timer: Timer?
    private let tick: @MainActor () -> Void

    init(screen: NSScreen?, tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        super.init()
        if #available(macOS 14, *), let screen {
            let link = screen.displayLink(target: self, selector: #selector(displayTick))
            let rate = Float(screen.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / Double(screen?.maximumFramesPerSecond ?? 60),
                              target: self, selector: #selector(displayTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func displayTick() { tick() }

    func setPaused(_ paused: Bool) {
        if #available(macOS 14, *) { (displayLink as? CADisplayLink)?.isPaused = paused }
        timer?.fireDate = paused ? .distantFuture : Date()
    }

    func stop() {
        if #available(macOS 14, *) { (displayLink as? CADisplayLink)?.invalidate() }
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }

    static func screen(for frame: CGRect) -> NSScreen? {
        let point = CGPoint(x: frame.midX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.midY)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func frames(for frame: CGRect) -> (@MainActor @Sendable () -> Void, AsyncStream<Double>) {
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let screen = screen(for: frame)
        let id = UUID()
        animationStreams[screen, default: [:]][id] = continuation
        if animationClocks[screen] == nil {
            animationClocks[screen] = DisplayFrameClock(screen: screen) {
                let now = ProcessInfo.processInfo.systemUptime
                for continuation in animationStreams[screen]?.values ?? [:].values {
                    continuation.yield(now)
                }
            }
        }
        animationClocks[screen]?.setPaused(false)
        return ({
            animationStreams[screen]?.removeValue(forKey: id)?.finish()
            if animationStreams[screen]?.isEmpty == true {
                animationStreams.removeValue(forKey: screen)
                animationClocks[screen]?.setPaused(true)
            }
        }, stream)
    }
}
