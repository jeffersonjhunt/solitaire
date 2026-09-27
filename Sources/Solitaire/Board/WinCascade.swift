import SwiftUI
import SolitaireEngine

/// The classic win cascade, in SwiftUI (no SpriteKit): kings first, the cards leap off the
/// foundations one after another, fall, bounce along the bottom of the board leaving a trail, and
/// leave the screen. The timeline stops once every card has gone. Not shown under Reduce Motion
/// (the board decides).
struct WinCascade: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    @State private var simulation = CascadeSimulation()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                simulation.advance(to: timeline.date, launches: launches, bounds: size,
                                   cardHeight: layout.metrics.cardHeight)
                for stamp in simulation.stamps {
                    guard let symbol = context.resolveSymbol(id: stamp.cardID) else { continue }
                    context.draw(symbol, at: stamp.center)
                }
                if simulation.isFinished && !finished {
                    Task { @MainActor in finished = true }     // not during the render pass
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

/// Plain physics in fixed time steps, so the motion and the trail spacing are the same at 60 and
/// 120 Hz. A reference type so the Canvas can advance it while drawing without triggering view
/// updates.
final class CascadeSimulation {
    struct Stamp { let cardID: Int; let center: CGPoint }
    private struct Flyer { let cardID: Int; var position: CGPoint; var velocity: CGVector }

    static let launchInterval: TimeInterval = 0.18
    static let step: TimeInterval = 1.0 / 120
    static let stampEvery = 2                       // steps: one trail stamp per 1/60 s
    static let gravity: CGFloat = 1600
    static let restitution: CGFloat = 0.72
    static let maxStamps = 1400

    private var start: Date?
    private var simulated: TimeInterval = 0
    private var steps = 0
    private var launched = 0
    private var total = 0
    private var flyers: [Flyer] = []
    private var rng = SplitMix64(seed: 2026)
    private(set) var stamps: [Stamp] = []

    /// Every card has launched and left the board.
    var isFinished: Bool { total > 0 && launched == total && flyers.isEmpty }

    func advance(to now: Date, launches: [(cardID: Int, from: CGPoint)], bounds: CGSize, cardHeight: CGFloat) {
        let start = self.start ?? now
        self.start = start
        total = launches.count
        // Catch up in fixed steps, but never more than a quarter second at once (after a stall).
        let target = min(now.timeIntervalSince(start), simulated + 0.25)
        let floor = bounds.height - cardHeight / 2        // the card's edge, not its centre, meets the bottom
        while simulated + Self.step <= target {
            simulated += Self.step
            steps += 1
            launch(upTo: simulated, launches)
            for i in flyers.indices {
                flyers[i].velocity.dy += Self.gravity * Self.step
                flyers[i].position.x += flyers[i].velocity.dx * Self.step
                flyers[i].position.y += flyers[i].velocity.dy * Self.step
                if flyers[i].position.y > floor, flyers[i].velocity.dy > 0 {
                    flyers[i].position.y = floor
                    flyers[i].velocity.dy *= -Self.restitution
                }
                if steps % Self.stampEvery == 0 {
                    stamps.append(Stamp(cardID: flyers[i].cardID, center: flyers[i].position))
                }
            }
            flyers.removeAll { $0.position.x < -200 || $0.position.x > bounds.width + 200 }
        }
        if stamps.count > Self.maxStamps {
            stamps.removeFirst(stamps.count - Self.maxStamps)
        }
    }

    private func launch(upTo time: TimeInterval, _ launches: [(cardID: Int, from: CGPoint)]) {
        while launched < launches.count, time >= Double(launched) * Self.launchInterval {
            let l = launches[launched]
            let speed = CGFloat(120 + rng.next() % 220)
            let direction: CGFloat = rng.next() % 2 == 0 ? -1 : 1
            flyers.append(Flyer(cardID: l.cardID, position: l.from,
                                velocity: CGVector(dx: direction * speed, dy: -CGFloat(rng.next() % 240))))
            launched += 1
        }
    }
}
