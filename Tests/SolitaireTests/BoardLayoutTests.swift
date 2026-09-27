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
    case iPhoneProMaxLandscape   // 956 × 440; side insets 2 × 62, home 21, bar 50
    case iPadThirdSplit          // 320-pt split column on an 11" iPad; status 24, bar 50
    case mac600                  // a 600-pt wide Mac window, 460 tall; toolbar 44

    var size: CGSize {
        switch self {
        case .iPhoneSEPortrait: CGSize(width: 375 - 8, height: 667 - 20 - 50)
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
        let readable = m.fans(faceDown: 6, faceUp: 9)
        #expect(readable.up >= m.cardHeight * BoardMetrics.readableFanRatio - 0.001)
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
