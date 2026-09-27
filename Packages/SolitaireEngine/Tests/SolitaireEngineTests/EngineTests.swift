import Foundation
import Testing
@testable import SolitaireEngine

typealias E = SolitaireEngine

// MARK: - Deal (acceptance: 52 distinct cards, 28 in the tableau with 7 face up, 24 in the stock)

@Suite struct Deal {
    @Test(arguments: [0, 1, 42, 2026, UInt64.max])
    func newDealHasTheRightShape(seed: UInt64) {
        for drawCount in [1, 3] {
            let s = E.newGame(drawCount: drawCount, seed: seed)
            #expect(Set(allCards(s).map(\.id)).count == 52)
            #expect(allCards(s).count == 52)
            #expect(s.tableau.map(\.count) == [1, 2, 3, 4, 5, 6, 7])
            #expect(s.tableau.flatMap { $0 }.filter(\.isFaceUp).count == 7)
            #expect(s.tableau.allSatisfy { $0.last!.isFaceUp })
            #expect(s.stock.count == 24 && s.stock.allSatisfy { !$0.isFaceUp })
            #expect(s.waste.isEmpty && s.foundations == [[], [], [], []])
            #expect(s.drawCount == drawCount && s.moveCount == 0 && !s.isWon && s.seed == seed)
        }
    }

    @Test func sameSeedSameDealDifferentSeedDifferentDeal() {
        #expect(E.newGame(drawCount: 1, seed: 7) == E.newGame(drawCount: 1, seed: 7))
        #expect(E.newGame(drawCount: 1, seed: 7) != E.newGame(drawCount: 1, seed: 8))
    }

    /// SplitMix64's published reference output for seed 0.
    @Test func splitMixMatchesTheReference() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    /// Pins the deal for one seed, so the same seed deals the same game on every platform and
    /// Swift version (this test runs on macOS and on Linux).
    @Test func dealIsStableAcrossPlatforms() {
        let s = E.newGame(drawCount: 1, seed: 42)
        #expect(s.tableau.map { $0.last!.id } == GoldenDeal.seed42Tops)
        #expect(s.stock.map(\.id) == GoldenDeal.seed42Stock)
    }
}

// MARK: - Legal and illegal moves (acceptance: every rule allowed, everything else refused)

@Suite struct Moves {
    func can(_ s: GameState, _ src: PileID, _ i: Int, _ dst: PileID) -> Bool {
        E.canMove(Move(source: src, index: i, destination: dst), in: s)
    }

    @Test func toFoundation() {
        let s = board(tableau: [[down("5C"), up("2H")], [up("9S"), up("8H")]],
                      waste: [up("3D"), up("AS")],
                      foundations: [[], foundation(.hearts, upTo: 1)])
        #expect(can(s, .waste, 1, .foundation(0)))            // ace onto an empty foundation
        #expect(can(s, .waste, 1, .foundation(2)))            // any empty foundation
        #expect(!can(s, .waste, 1, .foundation(1)))           // ace onto a non-empty one
        #expect(can(s, .tableau(0), 1, .foundation(1)))       // 2♥ on A♥: same suit, one higher
        #expect(!can(s, .tableau(0), 1, .foundation(0)))      // 2 onto empty
        #expect(!can(s, .waste, 0, .foundation(0)))           // not the waste top
        #expect(!can(s, .tableau(1), 0, .foundation(0)))      // a run of two cannot go up
    }

    @Test func foundationNeedsSameSuitAndNextRank() {
        let s = board(tableau: [[up("3H")], [up("3D")], [up("4H")]],
                      foundations: [foundation(.hearts, upTo: 2)])
        #expect(can(s, .tableau(0), 0, .foundation(0)))
        #expect(!can(s, .tableau(1), 0, .foundation(0)))      // wrong suit
        #expect(!can(s, .tableau(2), 0, .foundation(0)))      // skips a rank
    }

    @Test func tableauToTableau() {
        let s = board(tableau: [[down("2C"), up("9H"), up("8C"), up("7D")],
                                [up("10S")], [up("10H")], [up("9S")], [], [down("KC")]])
        #expect(can(s, .tableau(0), 1, .tableau(1)))          // 9♥-8♣-7♦ onto 10♠
        #expect(!can(s, .tableau(0), 1, .tableau(2)))         // same colour
        #expect(!can(s, .tableau(0), 1, .tableau(3)))         // wrong rank
        #expect(!can(s, .tableau(0), 2, .tableau(3)))         // 8♣ onto 9♠: same colour
        #expect(!can(s, .tableau(0), 3, .tableau(0)))         // onto its own pile
        #expect(!can(s, .tableau(0), 0, .tableau(1)))         // a face-down card
        #expect(!can(s, .tableau(0), 1, .tableau(4)))         // only a king onto an empty column
        #expect(!can(s, .tableau(3), 0, .tableau(5)))         // onto a face-down card
    }

    @Test func kingWithItsRunOntoAnEmptyColumn() {
        let s = board(tableau: [[down("2C"), up("KH"), up("QS")], []])
        #expect(can(s, .tableau(0), 1, .tableau(1)))
        #expect(!can(s, .tableau(0), 2, .tableau(1)))         // queen alone may not
    }

    @Test func wasteToTableau() {
        let s = board(tableau: [[up("8S")]], waste: [up("7C"), up("7H")])
        #expect(can(s, .waste, 1, .tableau(0)))
        #expect(!can(s, .waste, 0, .tableau(0)))              // only the top of the waste
    }

    @Test func foundationBackToTableau() {
        let s = board(tableau: [[up("4C")], [up("4H")]],
                      foundations: [foundation(.hearts, upTo: 3)])
        #expect(can(s, .foundation(0), 2, .tableau(0)))       // 3♥ onto 4♣
        #expect(!can(s, .foundation(0), 2, .tableau(1)))      // same colour
        #expect(!can(s, .foundation(0), 1, .tableau(0)))      // not the top card
        #expect(!can(s, .foundation(0), 2, .foundation(1)))   // foundation to foundation
    }

    @Test func nothingElse() {
        let s = board(tableau: [[up("KS"), up("QH"), up("5D")], [up("6C")]],
                      waste: [up("AS")], stock: [down("2D")])
        #expect(!can(s, .stock, 0, .waste))                   // drawing is not a move
        #expect(!can(s, .waste, 0, .stock))
        #expect(!can(s, .waste, 0, .waste))
        #expect(!can(s, .tableau(0), 0, .tableau(1)))         // K-Q-5 is not a built run
        #expect(!can(s, .tableau(9), 0, .tableau(1)))
        #expect(!can(s, .tableau(1), 0, .tableau(9)))
        #expect(!can(s, .tableau(1), 0, .foundation(4)))
        #expect(!can(s, .tableau(1), -1, .tableau(0)))
        #expect(!can(s, .tableau(1), 1, .tableau(0)))
        #expect(!can(board(), .waste, 0, .foundation(0)))     // empty waste
    }

    @Test func applyMovesTheRunAndFlipsTheUncoveredCardInOneMove() {
        var s = board(tableau: [[down("2C"), up("9H"), up("8C")], [up("10S")]])
        E.apply(Move(source: .tableau(0), index: 1, destination: .tableau(1)), to: &s)
        #expect(s.tableau[1].map(\.id) == [up("10S"), up("9H"), up("8C")].map(\.id))
        #expect(s.tableau[0] == [up("2C")])
        #expect(s.moveCount == 1)
    }

    @Test func applyDetectsTheWin() {
        var s = board(tableau: [[up("KS")]],
                      foundations: [foundation(.spades, upTo: 12), foundation(.hearts, upTo: 13),
                                    foundation(.diamonds, upTo: 13), foundation(.clubs, upTo: 13)])
        #expect(!s.isWon)
        E.apply(Move(source: .tableau(0), index: 0, destination: .foundation(0)), to: &s)
        #expect(s.isWon && E.isWon(s))
    }
}

// MARK: - Stock, draw modes and redeal (acceptance: draw 3 plays only the top; redeal reverses)

@Suite struct Stock {
    @Test func drawOneTurnsUpTheTopCard() {
        var s = board(stock: [down("2C"), down("7H")])
        E.drawFromStock(&s)
        #expect(s.waste == [up("7H")] && s.stock == [down("2C")] && s.moveCount == 1)
    }

    @Test func drawThreeOnlyTheTopOfTheWasteIsPlayable() {
        var s = board(tableau: [[up("8S")], [up("9C")]],
                      stock: [down("AD"), down("8H"), down("7D"), down("6D")], drawCount: 3)
        E.drawFromStock(&s)
        #expect(s.waste.map(\.id) == [up("6D"), up("7D"), up("8H")].map(\.id))  // 8♥ drawn last, on top
        #expect(s.waste.allSatisfy { $0.isFaceUp } && s.stock == [down("AD")])
        #expect(E.canMove(Move(source: .waste, index: 2, destination: .tableau(1)), in: s))   // 8♥ on 9♣
        #expect(!E.canMove(Move(source: .waste, index: 1, destination: .tableau(0)), in: s))  // 7♦ under it
        E.drawFromStock(&s)                                      // only one left: draws one
        #expect(s.waste.count == 4 && s.stock.isEmpty)
    }

    /// Under a draw-3 fan the cards often look like a built run (7♦ then 6♣); only the top card
    /// may still be played — never the card beneath it with the top riding along.
    @Test func cardsUnderTheWasteTopStayPutEvenWhenTheyLookLikeARun() {
        let s = board(tableau: [[up("8S")]], waste: [up("7D"), up("6C")], drawCount: 3)
        #expect(!E.canMove(Move(source: .waste, index: 0, destination: .tableau(0)), in: s))
        #expect(E.autoDestination(for: .waste, index: 0, in: s) == nil)
    }

    @Test(arguments: [1, 3])
    func redealRestoresTheStockInReverseSoTheSameCardsComeUpAgain(drawCount: Int) {
        var s = E.newGame(drawCount: drawCount, seed: 99)
        let stockBefore = s.stock
        var firstPass: [[Card]] = []
        while !s.stock.isEmpty { E.drawFromStock(&s); firstPass.append(s.waste) }
        let moves = s.moveCount

        E.drawFromStock(&s)                                      // redeal
        #expect(s.moveCount == moves + 1, "a redeal counts as one move")
        #expect(s.waste.isEmpty)
        #expect(s.stock == stockBefore, "same order, face down")
        #expect(s.stock.map(\.id) == firstPass.last!.reversed().map(\.id))

        var secondPass: [[Card]] = []
        while !s.stock.isEmpty { E.drawFromStock(&s); secondPass.append(s.waste) }
        #expect(secondPass == firstPass)
    }

    @Test func tappingAnEmptyStockWithAnEmptyWasteDoesNothing() {
        var s = board()
        E.drawFromStock(&s)
        #expect(s == board() && s.moveCount == 0)
    }
}

// MARK: - Tap-to-move (acceptance: never a no-op; king to an empty column by drag, not by tap)

@Suite struct TapToMove {
    func dest(_ s: GameState, _ src: PileID, _ i: Int) -> PileID? {
        E.autoDestination(for: src, index: i, in: s)
    }

    @Test func aSingleCardPrefersTheFoundation() {
        let s = board(tableau: [[up("2H")], [up("3S")]], foundations: [[], foundation(.hearts, upTo: 1)])
        #expect(dest(s, .tableau(0), 0) == .foundation(1))
    }

    @Test func runsGoToTheFirstFittingColumnAfterTheSourceWrappingAround() {
        let s = board(tableau: [[up("10D")], [], [up("8S")], [up("9C"), up("8H")], [], [up("9S")], [up("10H")]])
        // 9♣-8♥ at column 3 fits 10♦ (col 0) and 10♥ (col 6): scanning 4,5,6,0… picks 6.
        #expect(dest(s, .tableau(3), 0) == .tableau(6))
        #expect(dest(s, .tableau(5), 0) == .tableau(6))        // 9♠ → 10♥, never an empty column first
    }

    @Test func emptyColumnIsTheLastResortAndNeverANoOp() {
        let buried = board(tableau: [[down("3C"), up("KH")], []])
        #expect(dest(buried, .tableau(0), 1) == .tableau(1))   // uncovers a card: offered
        let alone = board(tableau: [[up("KH")], []])
        #expect(dest(alone, .tableau(0), 0) == nil)            // would only shuffle columns
        #expect(E.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: alone),
                "still possible by drag")
    }

    @Test func nothingFitsReturnsNil() {
        let s = board(tableau: [[up("5S")], [up("9H")]])
        #expect(dest(s, .tableau(0), 0) == nil)
        #expect(dest(s, .stock, 0) == nil)
    }

    /// Over many real positions: a tap target is always legal, and never a move that changes
    /// nothing (same pile, or a whole column onto an empty column).
    @Test func tapIsAlwaysLegalAndNeverANoOp() {
        var checked = 0
        for seed in UInt64(1)...40 {
            var s = E.newGame(drawCount: 1, seed: seed)
            for step in 0..<300 {
                let sources = [(PileID.waste, s.waste.count - 1)]
                    + (0..<4).map { (PileID.foundation($0), s.foundations[$0].count - 1) }
                    + (0..<7).flatMap { t in s.tableau[t].indices.map { (PileID.tableau(t), $0) } }
                for (src, i) in sources where i >= 0 {
                    guard let d = E.autoDestination(for: src, index: i, in: s) else { continue }
                    checked += 1
                    #expect(d != src)
                    #expect(E.canMove(Move(source: src, index: i, destination: d), in: s))
                    if case .tableau(let t) = d, s.tableau[t].isEmpty, case .tableau = src {
                        #expect(i > 0, "moved a whole column to an empty column")
                    }
                }
                let moves = legalMoves(s)
                if !moves.isEmpty && step % 3 != 0 {
                    E.apply(moves[(Int(seed) + step) % moves.count], to: &s)
                } else {
                    E.drawFromStock(&s)
                }
            }
        }
        #expect(checked > 1000, "the property must actually be exercised (checked \(checked))")
    }
}

// MARK: - Auto-finish and a full game (acceptance: a known-solvable seed plays to a win)

@Suite struct Finish {
    @Test func autoFinishIsOfferedOnlyWhenEverythingIsFaceUpAndDealtOut() {
        let open = board(tableau: [[up("2S"), up("AH")], [up("AS")]])
        #expect(E.canAutoFinish(open))
        #expect(!E.canAutoFinish(board(tableau: [[down("2S"), up("AH")]])))
        #expect(!E.canAutoFinish(board(tableau: [[up("AH")]], waste: [up("2S")])))
        #expect(!E.canAutoFinish(board(tableau: [[up("AH")]], stock: [down("2S")])))
    }

    @Test func autoFinishPlaysTheLowestRankFirstAndWins() {
        var s = board(tableau: [[up("2S"), up("AH")], [up("2H"), up("AS")]],
                      foundations: [[], [], foundation(.diamonds, upTo: 13), foundation(.clubs, upTo: 13)])
        var ranks: [Int] = []
        while let m = E.nextAutoFinishMove(in: s) {
            ranks.append(s[m.source][m.index].rank)
            E.apply(m, to: &s)
        }
        #expect(ranks == [1, 1, 2, 2])
        #expect(s.tableau.allSatisfy { $0.isEmpty })
    }

    @Test func aKnownSolvableSeedPlaysToAWin() {
        let end = playGreedily(E.newGame(drawCount: 1, seed: GoldenDeal.solvableSeed))
        #expect(end.isWon)
        #expect(end.foundations.allSatisfy { $0.count == 13 })
        #expect(!E.canAutoFinish(end), "nothing left to offer once won")
    }
}

/// Values pinned from the first run and checked on every platform since.
enum GoldenDeal {
    static let seed42Tops = [9, 8, 2, 50, 24, 49, 16]
    static let seed42Stock = [6, 28, 12, 39, 40, 0, 26, 25, 22, 4, 46, 36, 27, 42, 31, 17,
                              14, 43, 18, 13, 19, 1, 33, 7]
    /// The first seed (of 1...400, 44 winnable) that `playGreedily` wins with draw 1.
    static let solvableSeed: UInt64 = 4
}
