import SwiftUI
import SolitaireEngine

/// The classic win cascade, in SwiftUI (no SpriteKit): kings first, the cards leap off the
/// foundations one after another, fall, bounce along the bottom with a trail, and leave the
/// screen. Not shown at all under Reduce Motion (the caller decides).
struct WinCascade: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    @State private var simulation = CascadeSimulation()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                simulation.advance(to: timeline.date, launches: launches, bounds: size)
                for stamp in simulation.stamps {
                    guard let symbol = context.resolveSymbol(id: stamp.cardID) else { continue }
                    context.draw(symbol, at: stamp.center)
                }
            } symbols: {
                ForEach(foundations.flatMap { $0 }) { card in
                    CardView(card: card, width: layout.metrics.cardWidth).tag(card.id)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Kings first, across the four foundations, then queens, and so on down to the aces.
    private var launches: [(cardID: Int, from: CGPoint)] {
        (0..<13).reversed().flatMap { rank in
            (0..<4).compactMap { f -> (Int, CGPoint)? in
                guard foundations[f].indices.contains(rank) else { return nil }
                let slot = layout.slot(.foundation(f))
                return (foundations[f][rank].id, CGPoint(x: slot.midX, y: slot.midY))
            }
        }
    }
}

/// Plain physics, stepped per frame. A reference type so the Canvas can advance it while drawing
/// without triggering view updates.
final class CascadeSimulation {
    struct Stamp { let cardID: Int; let center: CGPoint }
    private struct Flyer { let cardID: Int; var position: CGPoint; var velocity: CGVector }

    static let launchInterval: TimeInterval = 0.18
    static let gravity: CGFloat = 1600
    static let restitution: CGFloat = 0.72
    static let maxStamps = 1400

    private var start: Date?
    private var last: Date?
    private var launched = 0
    private var flyers: [Flyer] = []
    private var rng = SplitMix64(seed: 2026)
    private(set) var stamps: [Stamp] = []

    func advance(to now: Date, launches: [(cardID: Int, from: CGPoint)], bounds: CGSize) {
        let start = self.start ?? now
        self.start = start
        let dt = min(now.timeIntervalSince(last ?? now), 1.0 / 30)
        last = now

        while launched < launches.count, now.timeIntervalSince(start) >= Double(launched) * Self.launchInterval {
            let l = launches[launched]
            let speed = CGFloat(120 + rng.next() % 220)
            let direction: CGFloat = rng.next() % 2 == 0 ? -1 : 1
            flyers.append(Flyer(cardID: l.cardID, position: l.from,
                                velocity: CGVector(dx: direction * speed, dy: -CGFloat(rng.next() % 240))))
            launched += 1
        }

        let floor = bounds.height
        for i in flyers.indices {
            flyers[i].velocity.dy += Self.gravity * dt
            flyers[i].position.x += flyers[i].velocity.dx * dt
            flyers[i].position.y += flyers[i].velocity.dy * dt
            if flyers[i].position.y > floor, flyers[i].velocity.dy > 0 {
                flyers[i].position.y = floor
                flyers[i].velocity.dy *= -Self.restitution
            }
            stamps.append(Stamp(cardID: flyers[i].cardID, center: flyers[i].position))
        }
        flyers.removeAll { $0.position.x < -200 || $0.position.x > bounds.width + 200 }
        if stamps.count > Self.maxStamps {
            stamps.removeFirst(stamps.count - Self.maxStamps)
        }
    }
}
