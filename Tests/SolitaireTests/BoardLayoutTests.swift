import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SolitaireEngine
@testable import Solitaire

/// The board area (inside safe areas and the toolbar) for the spec's layout acceptance sizes.
/// Derived from each device's points: screen − status bar/home indicator/side insets − toolbar.
enum BoardSize: String, CaseIterable {
    case iPhoneSEPortrait        // 375 × 667; status 20, bar 50
    case iPhoneSELandscape       // 667 × 375; bar 50 (no notch, no home indicator)
    case iPhoneProMaxLandscape   // 956 × 440; side insets 2 × 62, home 21, bar 50
    case iPadThirdSplit          // 320-pt split column on an 11" iPad; status 24, bar 50
    case mac600                  // a 600-pt wide Mac window, 460 tall; toolbar 44

    var size: CGSize {
        switch self {
        case .iPhoneSEPortrait: CGSize(width: 375 - 8, height: 667 - 20 - 50)
        case .iPhoneSELandscape: CGSize(width: 667 - 8, height: 375 - 50)
        case .iPhoneProMaxLandscape: CGSize(width: 956 - 124 - 8, height: 440 - 21 - 50)
        case .iPadThirdSplit: CGSize(width: 320 - 8, height: 1180 - 24 - 50)
        case .mac600: CGSize(width: 600 - 8, height: 460 - 44)
        }
    }

    var isTouch: Bool { self != .mac600 }
}

/// A position with the tallest column the rules allow: 6 face-down cards under a full K→A run.
func worstCaseState() -> GameState {
    let down = (2...7).map { Card(suit: .clubs, rank: $0, isFaceUp: false) }
    let run = (1...13).reversed().map { rank in
        Card(suit: rank % 2 == 1 ? .spades : .hearts, rank: rank, isFaceUp: true)
    }
    var s = SolitaireEngine.newGame(drawCount: 3, seed: 1)
    s.tableau = [[], [], [], [], [], [], down + run]
    s.stock = []
    s.waste = []
    return s
}

@Suite struct Metrics {
    @Test func followsTheSpecRatios() {
        let m = BoardMetrics(size: CGSize(width: 700, height: 2000), isTouch: false)
        #expect(abs(m.gap - 700 * 0.018) < 0.001)
        #expect(abs(m.cardWidth - (700 - 8 * m.gap) / 7) < 0.001)
        #expect(abs(m.cardHeight - m.cardWidth * 1.4) < 0.001)
        #expect(abs(m.cornerRadius - m.cardWidth * 0.09) < 0.001)
        #expect(abs(m.faceDownFan - m.cardHeight * 0.12) < 0.001)
        #expect(abs(m.faceUpFan - m.cardHeight * 0.29) < 0.001)
        #expect(!m.isCompressed)
    }

    @Test func boardWidthIsCappedAt900AndCentred() {
        let m = BoardMetrics(size: CGSize(width: 2000, height: 4000), isTouch: false)
        #expect(abs(m.cardWidth - (900 - 8 * 900 * 0.018) / 7) < 0.001)
        #expect(abs(m.leftEdge - (2000 - m.usedWidth) / 2) < 0.001)
    }

    @Test func gapNeverBelowFourPoints() {
        #expect(BoardMetrics(size: CGSize(width: 150, height: 2000), isTouch: false).gap == 4)
    }

    /// Decision D1: on short, wide boards cards are capped so a column of six face-down cards under
    /// a K→5 run keeps readable fans; a fresh deal is never squeezed.
    @Test(arguments: [BoardSize.iPhoneProMaxLandscape, .mac600])
    func shortWideBoardsCapTheCardSizeByHeight(_ board: BoardSize) {
        let size = board.size
        let m = BoardMetrics(size: size, isTouch: board.isTouch)
        let byWidth = (min(size.width, 900) - 8 * m.gap) / 7
        #expect(m.cardWidth < byWidth, "the height cap should bind here")
        // A real column: six face-down cards under K→5 (nine face-up cards, eight fan steps).
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 1)
        let down = (2...7).map { Card(suit: .clubs, rank: $0, isFaceUp: false) }
        let run = (5...13).reversed().map { Card(suit: $0 % 2 == 1 ? .spades : .hearts, rank: $0, isFaceUp: true) }
        s.tableau = [[], [], [], [], [], [], down + run]
        let column = BoardLayout(state: s, metrics: m).placements.filter { $0.pile == .tableau(6) }
        let upSteps = zip(column.dropFirst(6), column.dropFirst(7)).map { $1.frame.minY - $0.frame.minY }
        #expect(upSteps.count == 8)
        #expect(upSteps.allSatisfy { $0 >= m.cardHeight * BoardMetrics.readableFanRatio - 0.01 },
                "K→5 stays readable: \(upSteps.first ?? 0) vs \(m.cardHeight * BoardMetrics.readableFanRatio)")
        // …and the cap is no tighter than that: a K→4 run is already squeezed below readable.
        let longer = (4...13).reversed().map { Card(suit: $0 % 2 == 1 ? .spades : .hearts, rank: $0, isFaceUp: true) }
        s.tableau[6] = down + longer
        let tight = BoardLayout(state: s, metrics: m).placements.filter { $0.pile == .tableau(6) }
        #expect(tight[8].frame.minY - tight[7].frame.minY < m.cardHeight * BoardMetrics.readableFanRatio)
        #expect(m.fans(faceDown: 6, faceUp: 0) == (m.faceDownFan, m.faceUpFan), "a fresh deal is not squeezed")
    }

    /// Where height is plentiful (portrait phones, iPads) the cap never binds: the spec's width rule wins.
    @Test(arguments: [BoardSize.iPhoneSEPortrait, .iPadThirdSplit])
    func tallBoardsKeepTheWidthRule(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        #expect(abs(m.cardWidth - (min(board.size.width, 900) - 8 * m.gap) / 7) < 0.001)
    }

    /// Decision D2: touch cards narrower than 44 pt compress the gaps and widen the hit area.
    @Test func narrowTouchBoardsAreCompressedWithFullHitTargets() {
        let touch = BoardMetrics(size: BoardSize.iPadThirdSplit.size, isTouch: true)
        #expect(touch.isCompressed && touch.gap == 4)
        #expect(touch.hitWidth >= 44)
        let mouse = BoardMetrics(size: BoardSize.iPadThirdSplit.size, isTouch: false)
        #expect(!mouse.isCompressed)
    }

    /// Every touch board gives each card a tap target of at least 44 pt.
    @Test(arguments: BoardSize.allCases.filter(\.isTouch))
    func touchHitTargetsAreAtLeast44(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: true)
        #expect(m.hitWidth >= 44, "\(board): \(m.hitWidth)")
    }

    @Test func fansShrinkOnlyWhenAColumnWouldOverflow() {
        let m = BoardMetrics(size: CGSize(width: 700, height: 700), isTouch: false)
        #expect(m.fans(faceDown: 1, faceUp: 1) == (m.faceDownFan, m.faceUpFan))
        let squeezed = m.fans(faceDown: 6, faceUp: 12)
        #expect(squeezed.up < m.faceUpFan && squeezed.down < m.faceDownFan)
        #expect(abs(squeezed.up / squeezed.down - 0.29 / 0.12) < 0.001, "scaled together")
    }
}

/// Acceptance: the board lays out without clipping on iPhone SE portrait, iPhone Pro Max
/// landscape, iPad split view at one third, and a 600 pt wide Mac window.
@Suite struct NoClipping {
    @Test(arguments: BoardSize.allCases)
    func everyCardFitsTheBoard(_ board: BoardSize) {
        let m = BoardMetrics(size: board.size, isTouch: board.isTouch)
        for (name, state) in [("deal", SolitaireEngine.newGame(drawCount: 3, seed: 4)), ("worst", worstCaseState())] {
            var s = state
            if name == "deal" { SolitaireEngine.drawFromStock(&s) }   // three cards on the waste, fanned
            let layout = BoardLayout(state: s, metrics: m)
            let bounds = CGRect(origin: .zero, size: board.size).insetBy(dx: -0.001, dy: -0.001)
            for p in layout.placements {
                #expect(bounds.contains(p.frame), "\(board) \(name): \(p.card.id) at \(p.frame)")
            }
            // The top row and the tableau never overlap.
            let topRowBottom = m.topRowY + m.cardHeight
            #expect(layout.placements.filter { if case .tableau = $0.pile { true } else { false } }
                .allSatisfy { $0.frame.minY >= topRowBottom })
        }
        #expect(m.cardWidth >= 30, "\(board): cards too small to read (\(m.cardWidth) pt)")
    }
}

/// Renders the real board at each acceptance size to PNGs for a human to look at (they are
/// written under the test host's temporary directory, whose path is printed).
@MainActor @Suite struct Snapshots {
    @Test(arguments: BoardSize.allCases)
    func renderBoard(_ board: BoardSize) throws {
        for (name, state) in [("deal", SolitaireEngine.newGame(drawCount: 3, seed: 4)), ("worst", worstCaseState())] {
            var s = state
            if name == "deal" { SolitaireEngine.drawFromStock(&s) }
            let store = GameStore(drawCount: 3) { 4 }
            store.resume(from: s)
            let view = BoardView(store: store)
                .frame(width: board.size.width, height: board.size.height)
                .background(TableBackground())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-snapshots")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(board.rawValue)-\(name).png")
            #if os(macOS)
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            #else
            let data = try #require(renderer.uiImage?.pngData())
            #endif
            try data.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
    }
}

@MainActor @Suite struct MovingCards {
    /// A card on its way to another pile is drawn above every other card, so it never slides under
    /// a deeper column during the animation.
    @Test func movedCardsAreRaisedAboveEverything() throws {
        let store = GameStore(drawCount: 1) { 4 }
        let move = try #require(legalMoves(store.state).first {
            SolitaireEngine.autoDestination(for: $0.source, index: $0.index, in: store.state) != nil })
        let card = store.state[move.source][move.index]
        #expect(store.tap(pile: move.source, index: move.index))
        #expect(store.movedCardIDs.contains(card.id))
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
        let moved = try #require(layout.placements.first { $0.card.id == card.id })
        let others = layout.placements.filter { !store.movedCardIDs.contains($0.card.id) }
        #expect(others.allSatisfy { $0.zIndex < moved.zIndex })
    }

    /// Within every pile, later cards are always drawn above earlier ones — after a move, a draw, a
    /// new deal and a resume alike (a per-card raise once buried unmoved cards mid-pile).
    @Test func cardsStayInOrderWithinEveryPile() {
        let store = GameStore(drawCount: 3) { 4 }
        let m = BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false)
        func check(_ when: String) {
            let layout = BoardLayout(state: store.state, metrics: m, raised: store.movedCardIDs)
            let byPile = Dictionary(grouping: layout.placements, by: \.pile)
            for (pile, cards) in byPile {
                let z = cards.sorted { $0.index < $1.index }.map(\.zIndex)
                #expect(z == z.sorted() && Set(z).count == z.count, "\(when): \(pile) out of order")
            }
        }
        store.tapStock(); check("draw")
        if let m = legalMoves(store.state).first { store.drop(source: m.source, index: m.index, on: m.destination) }
        check("move")
        store.newGame(drawCount: 3); check("new deal")
        store.resume(from: worstCaseState()); check("resume")
    }

    @Test func theClockTickDoesNotLowerAMovingCard() {
        let store = GameStore(drawCount: 1) { 4 }
        store.tapStock()
        let moved = store.movedCardIDs
        #expect(!moved.isEmpty)
        store.tick()
        #expect(store.movedCardIDs == moved)
    }
}

@Suite struct VoiceOver {
    func roles(_ s: GameState) -> [Int: CardAccessibility] {
        let layout = BoardLayout(state: s, metrics: BoardMetrics(size: CGSize(width: 800, height: 900), isTouch: false))
        return Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.card.id, CardAccessibility.of($0, in: s)) })
    }

    @Test func buriedCardsAreHiddenAndTheStockIsNotReadCardByCard() {
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        SolitaireEngine.drawFromStock(&s)
        SolitaireEngine.drawFromStock(&s)
        let r = roles(s)
        #expect(s.stock.allSatisfy { r[$0.id] == .hidden })
        #expect(r[s.waste[0].id] == .hidden, "a buried waste card")
        #expect(r[s.waste[1].id] != .hidden, "the waste top")
        #expect(s.tableau.flatMap { $0 }.filter { !$0.isFaceUp }.allSatisfy { r[$0.id] == .hidden })
    }

    @Test func columnsSayWhatIsHiddenAndOnlyPlayableCardsAreButtons() {
        let s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        let r = roles(s)
        let top6 = s.tableau[6].last!
        #expect(r[top6.id]!.text.hasSuffix("column 7, 6 face-down cards under it"))
        #expect(r[s.tableau[0].last!.id]!.text.hasSuffix("column 1"))
        for t in 0..<7 {
            let card = s.tableau[t].last!
            let playable = SolitaireEngine.autoDestination(for: .tableau(t), index: s.tableau[t].count - 1, in: s) != nil
            #expect(r[card.id]!.isButton == playable)
        }
    }

    @Test func foundationTopIsNamedButNotAButton() {
        var s = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        s.foundations[0] = [Card(suit: .hearts, rank: 1, isFaceUp: true), Card(suit: .hearts, rank: 2, isFaceUp: true)]
        s.tableau = s.tableau.map { $0.filter { !($0.suit == .hearts && $0.rank <= 2) } }
        s.stock.removeAll { $0.suit == .hearts && $0.rank <= 2 }
        let r = roles(s)
        #expect(r[Card(suit: .hearts, rank: 2).id] == .label("2 of Hearts, foundation 1"))
        #expect(r[Card(suit: .hearts, rank: 1).id] == .hidden)
    }
}

@Suite struct Cascade {
    func launches() -> [(cardID: Int, from: CGPoint)] {
        (0..<52).map { ($0, CGPoint(x: 400, y: 60)) }
    }

    /// Same trail however often the screen refreshes. Measured over half a second, well under the
    /// trail cap — a saturated trail would make any two counts equal and prove nothing.
    @Test func trailDoesNotDependOnFrameRate() {
        func run(fps: Double) -> Int {
            let sim = CascadeSimulation()
            let t0 = Date()
            for frame in 0...Int(0.5 * fps) {
                sim.advance(to: t0.addingTimeInterval(Double(frame) / fps), launches: launches(),
                            bounds: CGSize(width: 800, height: 600), cardHeight: 100)
            }
            return sim.stamps.count
        }
        let at60 = run(fps: 60), at120 = run(fps: 120)
        #expect(at60 > 0 && at120 < CascadeSimulation.maxStamps, "must not saturate (\(at120))")
        #expect(at60 == at120)
    }

    @Test func cardsBounceOnTheBoardEdgeAndTheCascadeEnds() {
        let sim = CascadeSimulation()
        let t0 = Date()
        var frame = 0
        while !sim.isFinished && frame < 60 * 120 {
            sim.advance(to: t0.addingTimeInterval(Double(frame) / 60), launches: launches(),
                        bounds: CGSize(width: 800, height: 600), cardHeight: 100)
            #expect(sim.stamps.allSatisfy { $0.center.y <= 600 - 50 + 0.001 })
            frame += 1
        }
        #expect(sim.isFinished, "every card should leave the board")
    }
}
