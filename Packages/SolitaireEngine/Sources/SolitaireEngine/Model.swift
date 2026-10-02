import Foundation

/// Every pile is ordered bottom to top: `last` is the visible or playable card, and a tableau
/// run to move is `pile[index...]`.

public enum Suit: Int, Codable, CaseIterable, Sendable {
    case spades, hearts, diamonds, clubs

    public var isRed: Bool { self == .hearts || self == .diamonds }
}

public struct Card: Identifiable, Hashable, Codable, Sendable {
    public let suit: Suit
    public let rank: Int          // 1...13, ace low
    public var isFaceUp: Bool

    /// Stable 0...51, derived from suit and rank, so views track the same card across piles.
    public var id: Int { suit.rawValue * 13 + rank - 1 }

    public init(suit: Suit, rank: Int, isFaceUp: Bool = false) {
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
    }
}

public enum PileID: Hashable, Codable, Sendable {
    case stock, waste
    case foundation(Int)   // 0...3
    case tableau(Int)      // 0...6
}

public struct Move: Hashable, Codable, Sendable {
    public let source: PileID
    public let index: Int         // first card moved, within the source pile
    public let destination: PileID

    public init(source: PileID, index: Int, destination: PileID) {
        self.source = source
        self.index = index
        self.destination = destination
    }
}

/// The whole game: rendering, saving and testing all read from it.
public struct GameState: Codable, Sendable, Equatable {
    public var stock: [Card]      // last element is the top, drawn first
    public var waste: [Card]
    public var foundations: [[Card]]  // always 4
    public var tableau: [[Card]]      // always 7
    public var drawCount: Int         // 1 or 3
    public var moveCount: Int
    public var elapsed: TimeInterval
    public var isWon: Bool
    public var seed: UInt64           // the shuffle seed, for replay and tests
    /// Times the waste has been turned back over into the stock.
    public var redeals: Int

    /// Trips through the deck: the first is pass 1, and each redeal starts another.
    public var passes: Int { redeals + 1 }

    public init(stock: [Card], waste: [Card], foundations: [[Card]], tableau: [[Card]],
                drawCount: Int, moveCount: Int = 0, elapsed: TimeInterval = 0,
                isWon: Bool = false, seed: UInt64 = 0, redeals: Int = 0) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.drawCount = drawCount
        self.moveCount = moveCount
        self.elapsed = elapsed
        self.isWon = isWon
        self.seed = seed
        self.redeals = redeals
    }

    /// Decodes a saved game. Saves from before passes were counted have no `redeals` and resume
    /// with none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stock = try c.decode([Card].self, forKey: .stock)
        waste = try c.decode([Card].self, forKey: .waste)
        foundations = try c.decode([[Card]].self, forKey: .foundations)
        tableau = try c.decode([[Card]].self, forKey: .tableau)
        drawCount = try c.decode(Int.self, forKey: .drawCount)
        moveCount = try c.decode(Int.self, forKey: .moveCount)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        isWon = try c.decode(Bool.self, forKey: .isWon)
        seed = try c.decode(UInt64.self, forKey: .seed)
        redeals = try c.decodeIfPresent(Int.self, forKey: .redeals) ?? 0
    }

    /// The cards of any pile, bottom to top.
    public subscript(pile: PileID) -> [Card] {
        get {
            switch pile {
            case .stock: stock
            case .waste: waste
            case .foundation(let i): foundations[i]
            case .tableau(let i): tableau[i]
            }
        }
        set {
            switch pile {
            case .stock: stock = newValue
            case .waste: waste = newValue
            case .foundation(let i): foundations[i] = newValue
            case .tableau(let i): tableau[i] = newValue
            }
        }
    }
}
