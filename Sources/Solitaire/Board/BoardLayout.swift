import CoreGraphics
import SolitaireEngine

/// Where every card sits for a given state and metrics. All 52 cards are always placed, so a
/// card moving between piles is the same view animating to a new frame.
struct CardPlacement: Identifiable, Equatable {
    let card: Card
    let pile: PileID
    let index: Int
    let frame: CGRect
    let zIndex: Double
    /// Whether the card is visible edge-on rather than buried under the card above it.
    let isExposed: Bool
    var id: Int { card.id }
}

struct BoardLayout: Equatable {
    let metrics: BoardMetrics
    let placements: [CardPlacement]

    /// The empty-pile outline and drop target for every pile.
    func slot(_ pile: PileID) -> CGRect {
        let m = metrics
        let size = CGSize(width: m.cardWidth, height: m.cardHeight)
        switch pile {
        case .stock: return CGRect(origin: CGPoint(x: m.columnX(0), y: m.topRowY), size: size)
        case .waste: return CGRect(origin: CGPoint(x: m.columnX(1), y: m.topRowY), size: size)
        case .foundation(let f): return CGRect(origin: CGPoint(x: m.columnX(3 + f), y: m.topRowY), size: size)
        case .tableau(let t): return CGRect(origin: CGPoint(x: m.columnX(t), y: m.tableauY), size: size)
        }
    }

    init(state: GameState, metrics m: BoardMetrics) {
        self.metrics = m
        var out: [CardPlacement] = []
        func stack(_ cards: [Card], _ pile: PileID, _ origin: CGPoint, z: Double,
                   exposedFrom: Int? = nil, offset: (Int) -> CGSize = { _ in .zero }) {
            let firstExposed = exposedFrom ?? max(cards.count - 1, 0)
            for (i, card) in cards.enumerated() {
                let o = offset(i)
                out.append(CardPlacement(
                    card: card, pile: pile, index: i,
                    frame: CGRect(x: origin.x + o.width, y: origin.y + o.height,
                                  width: m.cardWidth, height: m.cardHeight),
                    zIndex: z + Double(i),
                    isExposed: i >= firstExposed))
            }
        }
        let empty = BoardLayout(metrics: m, placements: [])
        stack(state.stock, .stock, empty.slot(.stock).origin, z: 0)
        // Draw 3 fans the top three waste cards to the right, into the empty third column.
        let fanned = state.drawCount == 3 ? 3 : 1
        let firstFanned = max(state.waste.count - fanned, 0)
        stack(state.waste, .waste, empty.slot(.waste).origin, z: 100, exposedFrom: firstFanned) { i in
            CGSize(width: CGFloat(max(i - firstFanned, 0)) * m.cardWidth * 0.3, height: 0)
        }
        for f in 0..<4 {
            stack(state.foundations[f], .foundation(f), empty.slot(.foundation(f)).origin, z: 200)
        }
        for t in 0..<7 {
            let column = state.tableau[t]
            let down = column.dropLast().filter { !$0.isFaceUp }.count
            let up = max(column.count - 1 - down, 0)
            let fans = m.fans(faceDown: down, faceUp: up)
            var y: CGFloat = 0
            var offsets: [CGFloat] = []
            for card in column {
                offsets.append(y)
                y += card.isFaceUp ? fans.up : fans.down
            }
            stack(column, .tableau(t), empty.slot(.tableau(t)).origin, z: 300, exposedFrom: 0) { i in
                CGSize(width: 0, height: offsets[i])
            }
        }
        self.placements = out
    }

    private init(metrics: BoardMetrics, placements: [CardPlacement]) {
        self.metrics = metrics
        self.placements = placements
    }
}
