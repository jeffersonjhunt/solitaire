import CoreGraphics

/// Every size on the board, derived from the space available. Views read from this and use no
/// numbers of their own (spec: "Layout and visuals").
struct BoardMetrics: Equatable, Sendable {
    static let maxBoardWidth: CGFloat = 900
    static let minGap: CGFloat = 4
    static let minHitTarget: CGFloat = 44
    static let aspect: CGFloat = 1.4
    static let faceDownFanRatio: CGFloat = 0.12
    static let faceUpFanRatio: CGFloat = 0.29
    /// The deepest column that must always stay readable (decision D1): six face-down cards
    /// under a nine-card run (K→5), with its face-up fan no smaller than `readableFanRatio`.
    static let readableColumn = (faceDown: CGFloat(6), faceUp: CGFloat(9))
    /// A face-up fan of 0.2 × card height still shows each card's rank and suit.
    static let readableFanRatio: CGFloat = 0.2

    let size: CGSize
    let gap: CGFloat
    let cardWidth: CGFloat
    /// Touch layout whose cards are narrower than the 44 pt hit target: gaps are at their minimum
    /// and each card's hit area is widened to its whole column slot (decision D2 in the spec).
    let isCompressed: Bool

    var cardHeight: CGFloat { cardWidth * Self.aspect }
    var cornerRadius: CGFloat { cardWidth * 0.09 }
    var faceDownFan: CGFloat { cardHeight * Self.faceDownFanRatio }
    var faceUpFan: CGFloat { cardHeight * Self.faceUpFanRatio }
    /// Width actually used by the seven columns, centred in `size.width`.
    var usedWidth: CGFloat { 7 * cardWidth + 6 * gap }
    var leftEdge: CGFloat { (size.width - usedWidth) / 2 }
    var topRowY: CGFloat { gap }
    var tableauY: CGFloat { gap + cardHeight + gap }
    /// The tap target for one card: its column slot, at least 44 pt when compressed.
    var hitWidth: CGFloat { isCompressed ? cardWidth + gap : cardWidth }

    init(size: CGSize, isTouch: Bool) {
        self.size = size
        let boardWidth = min(size.width, Self.maxBoardWidth)
        var gap = max(boardWidth * 0.018, Self.minGap)
        var width = Self.cardWidth(boardWidth: boardWidth, gap: gap, height: size.height)
        let compressed = isTouch && width < Self.minHitTarget
        if compressed {
            gap = Self.minGap
            width = Self.cardWidth(boardWidth: boardWidth, gap: gap, height: size.height)
        }
        self.gap = gap
        self.cardWidth = max(width, 1)
        self.isCompressed = compressed
    }

    /// The spec's rule, (board width − 8 gaps) / 7, capped by height so that the top row plus the
    /// `readableColumn` fits with its fans squeezed no further than `readableFanRatio` (decision D1;
    /// only binds on short, wide boards such as a phone in landscape or a short Mac window).
    private static func cardWidth(boardWidth: CGFloat, gap: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = (boardWidth - 8 * gap) / 7
        let squeeze = readableFanRatio / faceUpFanRatio
        let fans = squeeze * (readableColumn.faceDown * faceDownFanRatio + readableColumn.faceUp * faceUpFanRatio)
        let heightInCards = 2 + fans                                        // top row + card + fans
        let byHeight = (height - 3 * gap) / heightInCards / aspect
        return min(byWidth, byHeight)
    }

    func columnX(_ column: Int) -> CGFloat {
        leftEdge + CGFloat(column) * (cardWidth + gap)
    }

    /// Fan offsets for a column: the spec's ratios, scaled down together (never up) when the
    /// column would otherwise run past the bottom of the board.
    func fans(faceDown: Int, faceUp: Int) -> (down: CGFloat, up: CGFloat) {
        let natural = CGFloat(faceDown) * faceDownFan + CGFloat(faceUp) * faceUpFan
        guard natural > 0 else { return (faceDownFan, faceUpFan) }
        let room = size.height - tableauY - gap - cardHeight
        let scale = min(1, max(room, 0) / natural)
        return (faceDownFan * scale, faceUpFan * scale)
    }
}
