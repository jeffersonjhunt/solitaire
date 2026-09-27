import CoreGraphics
import Foundation

/// macOS double-click is "the same as a tap" (spec). A double-click is two clicks, and the first
/// already moved the card, so the second would land on whatever it uncovered and move that too.
/// This drops a click that follows an accepted one within the double-click interval, near the same
/// point — so a double-click acts exactly once.
struct ClickFilter {
    let interval: TimeInterval
    let slop: CGFloat
    private var last: (time: Date, point: CGPoint)?

    init(interval: TimeInterval, slop: CGFloat = 6) {
        self.interval = interval
        self.slop = slop
    }

    /// Whether a click at `point` should act. Accepted clicks start a new double-click window.
    mutating func accept(at point: CGPoint, time: Date = Date()) -> Bool {
        if let last, time.timeIntervalSince(last.time) < interval,
           abs(point.x - last.point.x) <= slop, abs(point.y - last.point.y) <= slop {
            self.last = nil                         // the second click of a double-click: swallowed
            return false
        }
        last = (time, point)
        return true
    }
}
