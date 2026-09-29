#if DEBUG
import Foundation
import SolitaireEngine

/// Debug-only environment variables so UI tests start from a known position:
///   SOLITAIRE_SEED=<n>          deal seed n
///   SOLITAIRE_SCENARIO=<name>   a prepared position (see `state(named:)`)
///
/// Environment, not launch arguments: macOS treats unrecognised command-line arguments as files
/// to open, and an app launched to "open" a file skips its initial window — the UI-test launches
/// came up with a menu bar and no board.
enum UITestScenario {
    @MainActor
    static func storeFromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> GameStore? {
        let seed = environment["SOLITAIRE_SEED"].flatMap(UInt64.init)
        let scenario = environment["SOLITAIRE_SCENARIO"].flatMap(state(named:))
        guard seed != nil || scenario != nil else { return nil }
        let store = GameStore { seed ?? 4 }
        if let scenario { store.resume(from: scenario) }
        return store
    }

    /// - `almostWon`: ace to ten of every suit on the foundations; the J, Q, K of each suit face up
    ///   in four columns; stock and waste empty — Auto-finish is offered and wins.
    /// - `kingAlone`: a real deal, rearranged so column 1 holds only the K♥ and column 2 is empty —
    ///   the king can reach the empty column by drag but tapping it must do nothing.
    /// - `kingToAce`: column 1 holds a face-up run from K♠ down to A♠ (spades and hearts
    ///   alternating) and column 2 is empty, so the whole 13-card run can be dragged back and forth —
    ///   the drag Instruments measures (`make profile` launches this position).
    static func state(named name: String) -> GameState? {
        switch name {
        case "almostWon":
            var s = SolitaireEngine.newGame(drawCount: 1, seed: 1)
            let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
            s.foundations = suits.map { suit in (1...10).map { Card(suit: suit, rank: $0, isFaceUp: true) } }
            func run(_ suit: Suit) -> [Card] {
                (11...13).reversed().map { Card(suit: suit, rank: $0, isFaceUp: true) }
            }
            s.tableau = [run(.spades), run(.hearts), run(.diamonds), run(.clubs), [], [], []]
            s.stock = []
            s.waste = []
            return s
        case "kingAlone":
            var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
            let king = Card(suit: .hearts, rank: 13, isFaceUp: true)
            var rest = (s.stock + s.tableau[0] + s.tableau[1]).filter { $0.id != king.id }
            for t in 2..<7 { s.tableau[t].removeAll { $0.id == king.id } }
            rest = rest.map { var c = $0; c.isFaceUp = false; return c }
            s.stock = rest
            s.tableau[0] = [king]
            s.tableau[1] = []
            // Keep every column's last card face up after removing the king from it.
            for t in 2..<7 where !s.tableau[t].isEmpty { s.tableau[t][s.tableau[t].count - 1].isFaceUp = true }
            return s
        case "kingToAce":
            let run = (1...13).reversed().map { rank in
                Card(suit: rank % 2 == 1 ? .spades : .hearts, rank: rank, isFaceUp: true)
            }
            let runIDs = Set(run.map(\.id))
            var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
            var rest = (s.stock + s.tableau.flatMap { $0 })
                .filter { !runIDs.contains($0.id) }
                .map { var c = $0; c.isFaceUp = false; return c }
            s.tableau[0] = run
            s.tableau[1] = []
            // Columns 3–7 get 2–6 cards with the last face up, as in a deal; the rest is the stock.
            for t in 2..<7 {
                s.tableau[t] = Array(rest.prefix(t))
                rest.removeFirst(t)
                s.tableau[t][t - 1].isFaceUp = true
            }
            s.stock = rest
            s.waste = []
            return s
        default:
            return nil
        }
    }
}
#endif
