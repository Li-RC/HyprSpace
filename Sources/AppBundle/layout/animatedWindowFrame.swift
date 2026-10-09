import AppKit

// Cubic Hermite interpolation retains velocity when a layout retargets mid-flight.
struct WindowFrameAnimation {
    let start: CGRect
    let target: CGRect
    let began: Double
    let velocity: CGRect
    static let duration = 0.18

    init(from start: CGRect, to target: CGRect, at time: Double, replacing previous: WindowFrameAnimation? = nil) {
        self.start = start
        self.target = target
        began = time
        velocity = previous?.velocity(at: time) ?? CGRect(
            x: (target.origin.x - start.origin.x) * 3 / Self.duration,
            y: (target.origin.y - start.origin.y) * 3 / Self.duration,
            width: (target.width - start.width) * 3 / Self.duration,
            height: (target.height - start.height) * 3 / Self.duration)
    }

    func frame(at time: Double) -> CGRect {
        let t = min(1, max(0, (time - began) / Self.duration))
        if t == 0 { return start }
        if t == 1 { return target }
        let eased = t * t * (3 - 2 * t)
        let tangent = t * pow(1 - t, 2) * Self.duration
        return CGRect(x: start.origin.x + (target.origin.x - start.origin.x) * eased + velocity.origin.x * tangent,
                      y: start.origin.y + (target.origin.y - start.origin.y) * eased + velocity.origin.y * tangent,
                      width: max(1, start.width + (target.width - start.width) * eased + velocity.size.width * tangent),
                      height: max(1, start.height + (target.height - start.height) * eased + velocity.size.height * tangent))
    }

    func velocity(at time: Double) -> CGRect {
        let t = min(1, max(0, (time - began) / Self.duration))
        if t == 1 { return .zero }
        let slope = 6 * t * (1 - t) / Self.duration
        let tangentSlope = (1 - t) * (1 - 3 * t)
        return CGRect(x: (target.origin.x - start.origin.x) * slope + velocity.origin.x * tangentSlope,
                      y: (target.origin.y - start.origin.y) * slope + velocity.origin.y * tangentSlope,
                      width: (target.width - start.width) * slope + velocity.size.width * tangentSlope,
                      height: (target.height - start.height) * slope + velocity.size.height * tangentSlope)
    }
}
