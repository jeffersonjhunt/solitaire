import SwiftUI
import SolitaireEngine

/// The table: pile outlines plus all 52 cards, each placed by `BoardLayout`. A card moving
/// between piles is the same view animating to a new frame (0.2 s ease-out) — for every state
/// change: a tap, a draw, auto-finish steps, undo, a new deal. A flip rotates over 0.25 s.
/// Reduce Motion turns every animation off, including the win cascade.
struct BoardView: View {
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let moveAnimation = Animation.easeOut(duration: 0.2)
    static let flipAnimation = Animation.easeOut(duration: 0.25)

    var body: some View {
        GeometryReader { geo in
            let metrics = BoardMetrics(size: geo.size, isTouch: Self.isTouch)
            let layout = BoardLayout(state: store.state, metrics: metrics, raised: store.movedCardIDs)
            ZStack(alignment: .topLeading) {
                outlines(layout)
                ForEach(layout.placements) { p in
                    card(p, metrics)
                }
                if store.state.isWon && !reduceMotion {
                    WinCascade(foundations: store.state.foundations, layout: layout)
                        .id(store.state.seed)               // a fresh cascade for every win
                        .zIndex(2000)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : Self.moveAnimation, value: store.state)
        }
    }

    private func card(_ p: CardPlacement, _ metrics: BoardMetrics) -> some View {
        let role = CardAccessibility.of(p, in: store.state)
        return CardView(card: p.card, width: metrics.cardWidth, hasShadow: p.isExposed)
            .animation(reduceMotion ? nil : Self.flipAnimation, value: p.card.isFaceUp)
            .contentShape(Rectangle().inset(by: -(metrics.hitWidth - metrics.cardWidth) / 2))
            .onTapGesture { tapped(p) }
            .accessibilityElement()
            .accessibilityLabel(role.text)
            .accessibilityAddTraits(role.isButton ? .isButton : [])
            .accessibilityAction { tapped(p) }
            .accessibilityHidden(role == .hidden)
            .position(x: p.frame.midX, y: p.frame.midY)
            .zIndex(p.zIndex)
    }

    private func outlines(_ layout: BoardLayout) -> some View {
        let w = layout.metrics.cardWidth
        let state = store.state
        let redeal = state.stock.isEmpty && !state.waste.isEmpty
        let stockLabel = !state.stock.isEmpty ? "Stock, \(state.stock.count) cards"
            : redeal ? "Stock, empty. Redeal" : "Stock, empty"
        return ZStack(alignment: .topLeading) {
            // VoiceOver: the stock is always this one element (its cards are hidden). Taps on the
            // stock's cards reach `tapStock` through the cards themselves; this handles the empty stock.
            outline(layout.slot(.stock), w, symbol: redeal ? "arrow.counterclockwise" : nil,
                    label: stockLabel, spoken: true, action: { store.tapStock() })
            outline(layout.slot(.waste), w, label: "Waste, empty", spoken: state.waste.isEmpty)
            ForEach(0..<4, id: \.self) { f in
                outline(layout.slot(.foundation(f)), w, symbol: "a.square", label: "Foundation \(f + 1), empty",
                        spoken: state.foundations[f].isEmpty)
            }
            ForEach(0..<7, id: \.self) { t in
                outline(layout.slot(.tableau(t)), w, label: "Column \(t + 1), empty",
                        spoken: state.tableau[t].isEmpty)
            }
        }
    }

    /// A pile's outline. Gestures and accessibility attach before `.position`, so both cover the
    /// outline only (a positioned view fills the whole board).
    @ViewBuilder
    private func outline(_ rect: CGRect, _ width: CGFloat, symbol: String? = nil, label: String,
                         spoken: Bool, action: (() -> Void)? = nil) -> some View {
        let base = PileOutline(width: width, symbol: symbol)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHidden(!spoken)
        if let action {
            base
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .position(x: rect.midX, y: rect.midY)
        } else {
            base.position(x: rect.midX, y: rect.midY)
        }
    }

    private func tapped(_ p: CardPlacement) {
        if case .stock = p.pile {
            store.tapStock()
        } else {
            store.tap(pile: p.pile, index: p.index)
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

extension CardAccessibility {
    var text: String {
        switch self {
        case .hidden: ""
        case .label(let s), .button(let s): s
        }
    }

    var isButton: Bool {
        if case .button = self { true } else { false }
    }
}
