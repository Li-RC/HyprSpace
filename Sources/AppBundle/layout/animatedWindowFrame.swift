import AppKit

func animatedWindowFrame(from start: CGRect, to target: CGRect, progress: Double) -> CGRect {
    let t = CGFloat(min(1, max(0, progress)))
    let eased = 1 - pow(1 - t, 3)
    return CGRect(x: start.minX + (target.minX - start.minX) * eased,
                  y: start.minY + (target.minY - start.minY) * eased,
                  width: start.width + (target.width - start.width) * eased,
                  height: start.height + (target.height - start.height) * eased)
}
