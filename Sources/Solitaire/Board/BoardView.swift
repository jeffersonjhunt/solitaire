import SwiftUI
import SolitaireEngine

/// The table: pile outlines plus all 52 cards, each placed by `BoardLayout`. A card moving
/// between piles is the same view animating to a new frame (0.2 s ease-out); a flip rotates over
/// 0.25 s. Reduce Motion turns every animation off.
struct BoardView: View {
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let moveAnimation = Animation.easeOut(duration: 0.2)
    static let flipAnimation = Animation.easeOut(duration: 0.25)

    var body: some View {
        GeometryReader { geo in
            let metrics = BoardMetrics(size: geo.size, isTouch: Self.isTouch)
            let layout = BoardLayout(state: store.state, metrics: metrics)
            ZStack(alignment: .topLeading) {
                outlines(layout)
                ForEach(layout.placements) { p in
                    CardView(card: p.card, width: metrics.cardWidth, hasShadow: p.isExposed)
                        .animation(reduceMotion ? nil : Self.flipAnimation, value: p.card.isFaceUp)
                        .contentShape(Rectangle().inset(by: -(metrics.hitWidth - metrics.cardWidth) / 2))
                        .onTapGesture { tapped(p) }
                        .position(x: p.frame.midX, y: p.frame.midY)
                        .zIndex(p.zIndex)
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func outlines(_ layout: BoardLayout) -> some View {
        let w = layout.metrics.cardWidth
        let redeal = store.state.stock.isEmpty && !store.state.waste.isEmpty
        return ZStack(alignment: .topLeading) {
            outline(layout.slot(.stock), w, symbol: redeal ? "arrow.counterclockwise" : nil,
                    label: redeal ? "Redeal" : "Stock, empty", isEmpty: store.state.stock.isEmpty)
                .onTapGesture { act { store.tapStock() } }
            outline(layout.slot(.waste), w, label: "Waste, empty", isEmpty: store.state.waste.isEmpty)
            ForEach(0..<4, id: \.self) { f in
                outline(layout.slot(.foundation(f)), w, symbol: "a.square", label: "Foundation \(f + 1), empty",
                        isEmpty: store.state.foundations[f].isEmpty)
            }
            ForEach(0..<7, id: \.self) { t in
                outline(layout.slot(.tableau(t)), w, label: "Column \(t + 1), empty",
                        isEmpty: store.state.tableau[t].isEmpty)
            }
        }
    }

    /// A pile's outline; VoiceOver names it only while the pile is empty (otherwise its cards speak).
    private func outline(_ rect: CGRect, _ width: CGFloat, symbol: String? = nil, label: String,
                         isEmpty: Bool) -> some View {
        PileOutline(width: width, symbol: symbol)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHidden(!isEmpty)
    }

    private func tapped(_ p: CardPlacement) {
        if case .stock = p.pile {
            act { store.tapStock() }
        } else {
            act { store.tap(pile: p.pile, index: p.index) }
        }
    }

    /// Runs an intent with the move animation (or none under Reduce Motion).
    private func act(_ intent: () -> Void) {
        if reduceMotion {
            intent()
        } else {
            withAnimation(Self.moveAnimation, intent)
        }
    }

    static var isTouch: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }
}
