import SwiftUI
import SolitaireEngine

/// U2 placeholder board: every pile as a row of plain card labels, wired to the store's intents,
/// so the app shell is playable end to end. U3 replaces it with the real board.
struct ContentView: View {
    let store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusBar
            HStack(spacing: 16) {
                Button { store.tapStock() } label: {
                    Text(store.state.stock.isEmpty ? "↺" : "Stock \(store.state.stock.count)")
                }
                .accessibilityLabel(store.state.stock.isEmpty ? "Redeal" : "Stock")
                pile(.waste, store.state.waste.suffix(3), offset: max(store.state.waste.count - 3, 0))
                Spacer()
                ForEach(0..<4, id: \.self) { f in
                    pile(.foundation(f), store.state.foundations[f].suffix(1),
                         offset: max(store.state.foundations[f].count - 1, 0))
                }
            }
            Divider()
            ForEach(0..<7, id: \.self) { t in
                pile(.tableau(t), store.state.tableau[t][...], offset: 0)
            }
            Spacer()
        }
        .padding()
        .font(.system(.body, design: .monospaced))
        .sheet(isPresented: .constant(store.state.isWon)) {
            VStack(spacing: 12) {
                Text("You won").font(.title.bold())
                Text("\(store.state.moveCount) moves · \(Self.clock(store.state.elapsed))")
                Button("New Game") { store.newGame(drawCount: store.state.drawCount) }
            }
            .padding(40)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("Moves \(store.state.moveCount)")
            Text(Self.clock(store.state.elapsed))
            Spacer()
            if store.canAutoFinish {
                Button("Auto-finish") { store.autoFinish() }
            }
            Button("Undo") { store.undo() }.disabled(!store.canUndo)
            Menu("New") {
                Button("Draw 1") { store.newGame(drawCount: 1) }
                Button("Draw 3") { store.newGame(drawCount: 3) }
            }
        }
    }

    /// A pile as tappable labels; `offset` is the index of the first shown card in the pile.
    private func pile(_ id: PileID, _ cards: ArraySlice<Card>, offset: Int) -> some View {
        HStack(spacing: 4) {
            if cards.isEmpty {
                Text("[  ]").foregroundStyle(.secondary).accessibilityLabel(Self.name(id))
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                Text(card.isFaceUp ? Self.label(card) : "▒▒")
                    .foregroundStyle(card.isFaceUp && card.suit.isRed ? .red : .primary)
                    .onTapGesture { store.tap(pile: id, index: offset + i) }
                    .accessibilityLabel(card.isFaceUp ? Self.spoken(card) : "Face-down card")
            }
        }
    }

    static func label(_ card: Card) -> String {
        let rank = [1: "A", 11: "J", 12: "Q", 13: "K"][card.rank] ?? "\(card.rank)"
        return rank + ["♠", "♥", "♦", "♣"][card.suit.rawValue]
    }

    static func spoken(_ card: Card) -> String {
        let rank = [1: "Ace", 11: "Jack", 12: "Queen", 13: "King"][card.rank] ?? "\(card.rank)"
        return "\(rank) of \(["Spades", "Hearts", "Diamonds", "Clubs"][card.suit.rawValue])"
    }

    static func name(_ id: PileID) -> String {
        switch id {
        case .stock: "Stock"
        case .waste: "Waste"
        case .foundation(let f): "Foundation \(f + 1)"
        case .tableau(let t): "Column \(t + 1)"
        }
    }

    static func clock(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    ContentView(store: GameStore())
}
