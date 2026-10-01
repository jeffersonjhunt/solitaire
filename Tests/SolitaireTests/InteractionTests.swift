import CoreGraphics
import Foundation
import Testing
import SolitaireEngine
@testable import Solitaire

@MainActor @Suite struct Dragging {
    @Test func onlyPickableCardsStartADrag() {
        let store = makeStore()
        #expect(!store.beginDrag(pile: .tableau(6), index: 0), "face down")
        #expect(store.pendingDrag == nil)
        #expect(!store.beginDrag(pile: .stock, index: 23))
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        #expect(store.pendingDrag == GameStore.PendingDrag(source: .tableau(6), index: 6))
        store.cancelDrag()
        #expect(store.pendingDrag == nil)
    }

    /// Undo, a draw or any other change that moves cards ends a drag in progress (else the drag
    /// stayed pending and no other card could be dragged); the clock's tick does not.
    @Test func changesThatMoveCardsEndADrag() throws {
        let store = makeStore()
        let move = try #require(legalMoves(store.state).first)
        store.drop(source: move.source, index: move.index, on: move.destination)
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.tick()
        #expect(store.pendingDrag != nil, "a tick moves nothing")
        store.undo()
        #expect(store.pendingDrag == nil, "undo ends it")
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.tapStock()
        #expect(store.pendingDrag == nil, "a draw ends it")
        #expect(store.beginDrag(pile: .tableau(6), index: 6))
        store.resume(from: store.state)
        #expect(store.pendingDrag != nil, "resuming the same position moves nothing")
        store.newGame()
        #expect(store.pendingDrag == nil)
    }

    @Test func aDropEndsTheDragLegalOrNot() throws {
        let store = makeStore()
        let move = try #require(legalMoves(store.state).first)
        #expect(store.beginDrag(pile: move.source, index: move.index))
        #expect(store.drop(source: move.source, index: move.index, on: move.destination))
        #expect(store.pendingDrag == nil)
        #expect(store.beginDrag(pile: .tableau(0), index: 0))
        let before = store.state
        #expect(!store.drop(source: .tableau(0), index: 0, on: .tableau(0)))
        #expect(store.pendingDrag == nil && store.state == before)
    }
}

/// Spec "New games and the draw mode": New Game and the draw chip deal at once unless a game in
/// progress would be lost; then they only ask.
@MainActor @Suite struct NewGamesAndTheDrawMode {
    @Test func aFreshDealIsReplacedAtOnce() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        #expect(!store.isInProgress, "no move made yet")
        ui.requestNewGame(drawCount: 3, store: store)               // the chip
        #expect(ui.pendingNewGame == nil && store.state.drawCount == 3 && store.preferredDrawCount == 3)
        let seed = store.state.seed
        ui.requestNewGame(store: store)                             // New Game
        #expect(ui.pendingNewGame == nil && store.state.seed != seed && store.state.drawCount == 3,
                "a new deal in the same mode")
    }

    @Test func aGameInProgressIsAskedAboutAndKeptUntilConfirmed() {
        let store = makeStore(drawCount: 1)
        let ui = AppUI()
        store.tapStock()                                            // a draw counts as a move
        #expect(store.isInProgress)
        let before = store.state
        ui.requestNewGame(drawCount: 3, store: store)
        #expect(ui.pendingNewGame == NewGameRequest(drawCount: 3, switching: true))
        #expect(store.state == before && store.preferredDrawCount == 1, "nothing dealt or remembered yet")
        #expect(ui.pendingNewGame?.title == "Switch to Draw 3?")
        #expect(ui.pendingNewGame?.confirm == "Start New Game")
        ui.requestNewGame(store: store)
        #expect(ui.pendingNewGame == NewGameRequest(drawCount: 1, switching: false))
        #expect(ui.pendingNewGame?.title == "Start a new game?" && ui.pendingNewGame?.message == "This one will be lost.")
        #expect(store.state == before)
    }

    @Test func aWonGameIsReplacedAtOnce() {
        let store = makeStore(drawCount: 3)
        let ui = AppUI()
        let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
        store.resume(from: GameState(stock: [], waste: [],
                                     foundations: suits.map { s in (1...13).map { Card(suit: s, rank: $0, isFaceUp: true) } },
                                     tableau: Array(repeating: [], count: 7), drawCount: 3, moveCount: 120, isWon: true))
        #expect(!store.isInProgress, "won: nothing to lose")
        ui.requestNewGame(drawCount: 1, store: store)
        #expect(ui.pendingNewGame == nil && store.state.drawCount == 1 && !store.state.isWon)
    }

    /// The resumed game's mode is the last deal's: New Game continues in it.
    @Test func resumingRemembersTheGamesMode() {
        let store = makeStore(drawCount: 1)
        var saved = makeStore(drawCount: 3).state
        saved.moveCount = 5
        store.resume(from: saved)
        #expect(store.preferredDrawCount == 3)
        store.newGame()
        #expect(store.state.drawCount == 3)
    }

    @Test func anInvalidCountBecomesDrawOne() {
        let store = makeStore(drawCount: 3)
        AppUI().requestNewGame(drawCount: 7, store: store)
        #expect(store.state.drawCount == 1)
    }
}

@MainActor @Suite struct Haptics {
    /// Light on a move, soft on a draw, success on a win — and nothing when a tap or drop fails.
    @Test func eventsForMovesDrawsAndWinsOnly() throws {
        let store = makeStore()
        #expect(store.feedback == nil)
        _ = store.tap(pile: .tableau(0), index: 5)                   // no such card
        _ = store.drop(source: .tableau(6), index: 0, on: .tableau(0))
        #expect(store.feedback == nil, "nothing on failure")
        store.tapStock()
        #expect(store.feedback?.kind == .draw)
        let move = try #require(legalMoves(store.state).first)
        store.drop(source: move.source, index: move.index, on: move.destination)
        #expect(store.feedback?.kind == .move)
        let first = store.feedback
        store.tapStock()
        store.tapStock()
        #expect(store.feedback?.kind == .draw && store.feedback != first)
        let almostWon = try #require(UITestScenario.state(named: "almostWon"))
        store.resume(from: almostWon)
        while let m = SolitaireEngine.nextAutoFinishMove(in: store.state) {
            store.drop(source: m.source, index: m.index, on: m.destination)
        }
        #expect(store.state.isWon && store.feedback?.kind == .win)
    }
}

@Suite struct DropTargets {
    let metrics = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)

    @Test func theNearestPileWins() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let col3 = layout.frame(of: .tableau(3))
        #expect(layout.dropTarget(for: CGPoint(x: col3.midX, y: col3.maxY + 40)) == .tableau(3))
        let f2 = layout.slot(.foundation(2))
        #expect(layout.dropTarget(for: CGPoint(x: f2.midX, y: f2.midY)) == .foundation(2))
    }

    /// Released back over its own column, a card lands on its own column — an illegal move, so it
    /// springs back — instead of jumping to whichever other pile is next nearest.
    @Test func releasingOverItsOwnColumnSpringsBack() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let own = layout.frame(of: .tableau(5))
        let target = layout.dropTarget(for: CGPoint(x: own.midX, y: own.midY))
        #expect(target == .tableau(5))
        #expect(!SolitaireEngine.canMove(Move(source: .tableau(5), index: 5, destination: .tableau(5)), in: s))
    }

    @Test func aColumnFrameReachesItsLastCard() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let last = layout.placements.last { $0.pile == .tableau(6) }!
        #expect(layout.frame(of: .tableau(6)).maxY == last.frame.maxY)
        #expect(layout.frame(of: .foundation(0)) == layout.slot(.foundation(0)))
    }
}

@Suite struct DoubleClick {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// Feeds clicks (point, seconds after t0) through one filter; returns which ones acted.
    func acted(_ clicks: [(CGFloat, CGFloat, Double)]) -> [Bool] {
        var f = ClickFilter(interval: 0.5)
        return clicks.map { f.accept(at: CGPoint(x: $0.0, y: $0.1), time: t0.addingTimeInterval($0.2)) }
    }

    @Test func aDoubleOrTripleClickActsOnce() {
        // the first click acts; the second (0.2 s later, 2 pt away) and a third are swallowed
        #expect(acted([(10, 10, 0), (12, 11, 0.2), (12, 11, 0.3)]) == [true, false, false])
        // …until the clicks pause for longer than the interval
        #expect(acted([(10, 10, 0), (10, 10, 0.2), (10, 10, 0.9)]) == [true, false, true])
    }

    @Test func separateClicksAllAct() {
        // somewhere else, then too late to be a double-click
        #expect(acted([(10, 10, 0), (200, 10, 0.1), (200, 10, 1.0)]) == [true, true, true])
    }
}

@Suite struct Routing {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    func routes(_ taps: [(PileID, Double)], mac: Bool = true) -> [TapRouter.Action] {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: mac)
        return taps.map { r.route($0.0, at: CGPoint(x: 10, y: 10), time: t0.addingTimeInterval($0.1)) }
    }

    /// Every click on the stock draws, however fast — the double-click filter is for card moves.
    @Test func fastClicksOnTheStockAllDraw() {
        #expect(routes([(.stock, 0), (.stock, 0.1), (.stock, 0.2)]) == [.draw, .draw, .draw])
    }

    @Test func aMacDoubleClickOnACardMovesOnce() {
        #expect(routes([(.tableau(2), 0), (.tableau(2), 0.2)]) == [.move, .ignore])
        #expect(routes([(.tableau(2), 0), (.tableau(2), 0.2)], mac: false) == [.move, .move], "iOS taps all act")
    }

    @Test func accessibilityActionsAlwaysAct() {
        var r = TapRouter(clicks: ClickFilter(interval: 0.5), filtersRepeatClicks: true)
        #expect(r.route(.waste, at: nil) == .move)
        #expect(r.route(.waste, at: nil) == .move)
    }
}

@Suite struct Scenarios {
    @Test(arguments: ["almostWon", "kingAlone", "kingToAce"])
    func scenariosAreRealPositions(_ name: String) throws {
        let s = try #require(UITestScenario.state(named: name))
        let cards = s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
        #expect(cards.count == 52 && Set(cards.map(\.id)).count == 52)
        #expect(s.tableau.allSatisfy { $0.isEmpty || $0.last!.isFaceUp })
    }

    @Test func scenariosSetUpWhatTheUITestsNeed() throws {
        let won = try #require(UITestScenario.state(named: "almostWon"))
        #expect(SolitaireEngine.canAutoFinish(won))
        let king = try #require(UITestScenario.state(named: "kingAlone"))
        #expect(king.tableau[0] == [Card(suit: .hearts, rank: 13, isFaceUp: true)] && king.tableau[1].isEmpty)
        #expect(SolitaireEngine.autoDestination(for: .tableau(0), index: 0, in: king) == nil)
        #expect(SolitaireEngine.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: king))
    }

    /// The profiling position: a whole King→Ace run that can be picked up and moved as one.
    @Test func kingToAceIsAThirteenCardRunThatMovesWhole() throws {
        let s = try #require(UITestScenario.state(named: "kingToAce"))
        let run = s.tableau[0]
        #expect(run.map(\.rank) == Array((1...13).reversed()) && run.allSatisfy(\.isFaceUp))
        #expect(zip(run, run.dropFirst()).allSatisfy { $0.suit.isRed != $1.suit.isRed })
        #expect(s.tableau[1].isEmpty)
        #expect(SaveValidation.isResumable(s), "a position a real game could reach")
        #expect(SolitaireEngine.canPickUp(from: .tableau(0), index: 0, in: s))
        #expect(SolitaireEngine.canMove(Move(source: .tableau(0), index: 0, destination: .tableau(1)), in: s))
    }
}
