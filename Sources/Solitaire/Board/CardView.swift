import SwiftUI
import SolitaireEngine

/// One card, drawn in SwiftUI (no images). Face: rank and small suit top-left at width × 0.36 and
/// × 0.28, a large suit bottom-right at × 0.62, in a rounded rectangle with a hairline border and a
/// 1 pt shadow. Back: a diagonal pattern in one colour with an inset border. Flipping rotates about
/// the Y axis; the face never inverts in dark mode.
struct CardView: View {
    let card: Card
    let width: CGFloat
    var isHighlighted = false
    /// False for cards buried in a stacked pile (stock, waste, foundation): only the top card casts
    /// a shadow, or 20 stacked shadows add up to a dark smear.
    var hasShadow = true

    var body: some View {
        FlippingCard(angle: card.isFaceUp ? 0 : 180, card: card, width: width, hasShadow: hasShadow)
            .frame(width: width, height: width * BoardMetrics.aspect)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: width * 0.09).strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(card.isFaceUp ? Self.spokenName(card) : "Face-down card")
    }

    static func rankText(_ rank: Int) -> String {
        [1: "A", 11: "J", 12: "Q", 13: "K"][rank] ?? "\(rank)"
    }

    static func suitSymbol(_ suit: Suit) -> String {
        ["♠", "♥", "♦", "♣"][suit.rawValue]
    }

    static func spokenName(_ card: Card) -> String {
        let rank = [1: "Ace", 11: "Jack", 12: "Queen", 13: "King"][card.rank] ?? "\(card.rank)"
        return "\(rank) of \(["Spades", "Hearts", "Diamonds", "Clubs"][card.suit.rawValue])"
    }
}

/// Rotates about the Y axis and shows the side facing the viewer: the face below 90°, the back
/// (unmirrored) from 90° on — so mid-flip never shows both sides at once.
private struct FlippingCard: View, Animatable {
    var angle: Double
    let card: Card
    let width: CGFloat
    let hasShadow: Bool

    /// Nonisolated: `Animatable` is not main-actor isolated, and this is only a stored Double.
    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        Group {
            if angle < 90 {
                CardFace(card: card, width: width, hasShadow: hasShadow)
            } else {
                CardBack(width: width, hasShadow: hasShadow)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

private struct CardFace: View {
    let card: Card
    let width: CGFloat
    let hasShadow: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
        let ink = card.suit.isRed ? Color("CardRed") : Color("CardBlack")
        shape
            .fill(Color("CardFace"))
            .overlay(shape.strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(hasShadow ? 0.3 : 0), radius: 1, y: 1)
            .overlay(alignment: .topLeading) {
                HStack(alignment: .firstTextBaseline, spacing: width * 0.01) {
                    Text(CardView.rankText(card.rank))
                        .font(.system(size: width * 0.36, weight: .semibold, design: .rounded))
                    Text(CardView.suitSymbol(card.suit))
                        .font(.system(size: width * 0.28))
                }
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.leading, width * 0.07)
                .padding(.top, width * 0.02)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(CardView.suitSymbol(card.suit))
                    .font(.system(size: width * 0.62))
                    .foregroundStyle(ink)
                    .padding(.trailing, width * 0.06)
                    .padding(.bottom, width * 0.01)
            }
            .environment(\.colorScheme, .light)
    }
}

private struct CardBack: View {
    let width: CGFloat
    let hasShadow: Bool

    var body: some View {
        let radius = width * 0.09
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Color("CardFace"))
            .overlay {
                let inset = width * 0.07
                RoundedRectangle(cornerRadius: max(radius - inset, 1), style: .continuous)
                    .fill(Color("CardBack"))
                    .overlay {
                        DiagonalPattern(spacing: width * 0.1)
                            .stroke(Color("CardFace").opacity(0.35), lineWidth: max(width * 0.02, 0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: max(radius - inset, 1), style: .continuous))
                    .padding(inset)
            }
            .overlay(shape.strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(hasShadow ? 0.3 : 0), radius: 1, y: 1)
    }
}

/// Repeating diagonal lines, both directions, filling the rect.
private struct DiagonalPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = max(spacing, 2)
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += step
        }
        return p
    }
}

/// An empty pile's outline on the table.
struct PileOutline: View {
    let width: CGFloat
    var symbol: String?

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            .background(RoundedRectangle(cornerRadius: width * 0.09).fill(Color.black.opacity(0.08)))
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: width * 0.35))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .frame(width: width, height: width * BoardMetrics.aspect)
    }
}
