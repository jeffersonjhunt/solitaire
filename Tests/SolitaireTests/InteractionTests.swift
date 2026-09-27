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

@MainActor @Suite struct DrawMode {
    @Test func toggleChangesTheNextDealNotThisOne() {
        let store = makeStore(drawCount: 1)
        store.toggleDrawMode()
        #expect(store.preferredDrawCount == 3 && store.state.drawCount == 1)
        store.newGame()
        #expect(store.state.drawCount == 3)
        store.newGame(drawCount: 1)
        #expect(store.preferredDrawCount == 1, "an explicit choice is remembered")
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

    @Test func theNearestPileWinsAndTheSourceIsExcluded() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let layout = BoardLayout(state: s, metrics: metrics)
        let col3 = layout.frame(of: .tableau(3))
        #expect(layout.dropTarget(for: CGPoint(x: col3.midX, y: col3.maxY + 40), from: .tableau(0)) == .tableau(3))
        let f2 = layout.slot(.foundation(2))
        #expect(layout.dropTarget(for: CGPoint(x: f2.midX, y: f2.midY), from: .waste) == .foundation(2))
        // Over its own column, a drag goes to the nearest *other* pile.
        let own = layout.frame(of: .tableau(5))
        #expect(layout.dropTarget(for: CGPoint(x: own.midX, y: own.midY), from: .tableau(5)) != .tableau(5))
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

    @Test func aDoubleClickActsOnce() {
        // first click acts, the second (0.2 s later, 2 pt away) is swallowed, a third acts again
        #expect(acted([(10, 10, 0), (12, 11, 0.2), (12, 11, 0.3)]) == [true, false, true])
    }

    @Test func separateClicksAllAct() {
        // somewhere else, then too late to be a double-click
        #expect(acted([(10, 10, 0), (200, 10, 0.1), (200, 10, 1.0)]) == [true, true, true])
    }
}

@Suite struct Scenarios {
    @Test(arguments: ["almostWon", "kingAlone"])
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
}
